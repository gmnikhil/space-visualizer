import Foundation
import Combine

public final class VisualFeatureStore: ObservableObject {
    @Published public private(set) var features: AudioFeatures = .settled
    public init() {}
    public func update(_ next: AudioFeatures) {
        if features != next { features = next }
    }
}

/// Serial DSP worker with a single overwrite-only result slot. No main-queue jobs per frame.
public final class AnalysisWorker {
    private let queue = DispatchQueue(label: "com.resonant.analysis", qos: .userInteractive)
    private let pipeline: AudioFeaturePipeline
    private let lock = NSLock()
    private var latest: AudioFeatures?
    private var producedAt: UInt64 = 0
    private var timer: DispatchSourceTimer?

    public init(pipeline: AudioFeaturePipeline) { self.pipeline = pipeline }

    public func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(4), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            guard let self, let next = self.pipeline.poll() else { return }
            self.lock.lock()
            self.latest = next
            self.producedAt = DispatchTime.now().uptimeNanoseconds
            self.lock.unlock()
        }
        self.timer = timer
        timer.resume()
    }

    public func snapshot() -> AudioFeatures? {
        lock.lock()
        defer { lock.unlock() }
        guard DispatchTime.now().uptimeNanoseconds - producedAt <= 250_000_000 else { return nil }
        return latest
    }

    /// Called on the owner/UI thread, never from the worker queue.
    public func stop() {
        timer?.cancel()
        timer = nil
        queue.sync {}
        lock.lock()
        latest = nil
        producedAt = 0
        lock.unlock()
    }
}
