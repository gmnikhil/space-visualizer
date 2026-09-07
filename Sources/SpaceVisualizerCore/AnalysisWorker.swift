import Foundation
import Combine

public final class VisualFeatureStore: ObservableObject {
    @Published public private(set) var features: AudioFeatures = .settled
    public init() {}
    public func update(_ next: AudioFeatures) {
        if features != next { features = next }
    }
}

/// A latest-only, lock-protected feature handoff for display cadence. It does
/// not publish Combine events for every audio frame.
public final class LatestAudioFeatures: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AudioFeatures = .settled
    private var publicationCountValue: UInt64 = 0

    public init() {}

    public func update(_ next: AudioFeatures) {
        lock.lock()
        if value != next {
            value = next
            publicationCountValue &+= 1
        }
        lock.unlock()
    }

    public var publicationCount: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return publicationCountValue
    }

    public func snapshot() -> AudioFeatures {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Serial DSP worker with a single overwrite-only result slot. No main-queue jobs per frame.
public final class AnalysisWorker {
    private let queue = DispatchQueue(label: "com.space-visualizer.analysis", qos: .userInteractive)
    private let pipeline: AudioFeaturePipeline
    private let onFeatures: ((AudioFeatures) -> Void)?
    private let clock: AudioTimestampClock
    private let maximumSampleAgeNanoseconds: UInt64
    public let telemetry: AnalysisTelemetry
    private let lock = NSLock()
    private var latest: AudioFeatures?
    private var staleWasPublished = false
    private var timer: DispatchSourceTimer?

    public init(
        pipeline: AudioFeaturePipeline,
        onFeatures: ((AudioFeatures) -> Void)? = nil,
        clock: AudioTimestampClock = SystemAudioTimestampClock(),
        maximumSampleAgeNanoseconds: UInt64 = AudioTiming.maximumFreshSampleAgeNanoseconds,
        telemetry: AnalysisTelemetry = AnalysisTelemetry()
    ) {
        self.pipeline = pipeline
        self.onFeatures = onFeatures
        self.clock = clock
        self.maximumSampleAgeNanoseconds = maximumSampleAgeNanoseconds
        self.telemetry = telemetry
    }

    public func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(4), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let pollTime = self.clock.nowNanoseconds()
            guard let next = self.pipeline.poll(nowNanoseconds: pollTime) else {
                self.publishExpiredInputIfNeeded(nowNanoseconds: self.clock.nowNanoseconds())
                return
            }
            let finishedAt = DispatchTime.now().uptimeNanoseconds
            let duration = finishedAt >= startedAt ? finishedAt - startedAt : 0
            let mailboxAge = self.clock.ageNanoseconds(
                of: next.timestamp,
                nowNanoseconds: self.clock.nowNanoseconds()
            )
            self.telemetry.recordAnalysis(
                durationNanoseconds: duration,
                mailboxAgeNanoseconds: mailboxAge
            )
            self.lock.lock()
            self.latest = next
            self.lock.unlock()
            if next.isFresh {
                self.staleWasPublished = false
                self.onFeatures?(next)
            } else if !self.staleWasPublished {
                self.staleWasPublished = true
                self.onFeatures?(next)
            }
        }
        self.staleWasPublished = false
        self.timer = timer
        telemetry.recordWorkerStarted()
        timer.resume()
    }

    public func snapshot(nowNanoseconds: UInt64? = nil) -> AudioFeatures? {
        lock.lock()
        let next = latest
        lock.unlock()
        guard let next, next.isFresh else { return nil }
        guard let age = clock.ageNanoseconds(
            of: next.timestamp,
            nowNanoseconds: nowNanoseconds ?? clock.nowNanoseconds()
        ), age <= maximumSampleAgeNanoseconds else { return nil }
        return next
    }

    private func publishExpiredInputIfNeeded(nowNanoseconds: UInt64) {
        guard !staleWasPublished else { return }
        lock.lock()
        let next = latest
        lock.unlock()
        guard let next, next.isFresh,
              let age = clock.ageNanoseconds(of: next.timestamp, nowNanoseconds: nowNanoseconds),
              age > maximumSampleAgeNanoseconds else { return }
        staleWasPublished = true
        onFeatures?(AudioFeatures(
            timestamp: next.timestamp,
            rms: 0,
            peak: 0,
            bass: 0,
            mids: 0,
            highs: 0,
            bands: [],
            isSilent: true,
            isFresh: false,
            generation: next.generation
        ))
    }

    /// Called on the owner/UI thread, never from the worker queue.
    public func stop() {
        guard timer != nil else { return }
        timer?.cancel()
        timer = nil
        queue.sync {}
        staleWasPublished = false
        telemetry.recordWorkerStopped()
        lock.lock()
        latest = nil
        lock.unlock()
    }
}
