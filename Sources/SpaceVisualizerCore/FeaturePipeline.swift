import Foundation

public final class AudioFeaturePipeline: @unchecked Sendable {
    public let collector: PCMBufferCollector
    public let analyzer: AudioAnalyzer
    public let mailbox: AudioFrameMailbox
    public let clock: AudioTimestampClock
    public let maximumSampleAgeNanoseconds: UInt64
    private var smoother = FeatureSmoother(attack: 0.7, release: 0.2)
    private var previousTimestampNanoseconds: UInt64?

    public init(
        collector: PCMBufferCollector,
        analyzer: AudioAnalyzer,
        mailbox: AudioFrameMailbox = AudioFrameMailbox(),
        clock: AudioTimestampClock = SystemAudioTimestampClock(),
        maximumSampleAgeNanoseconds: UInt64 = AudioTiming.maximumFreshSampleAgeNanoseconds
    ) {
        self.collector = collector
        self.analyzer = analyzer
        self.mailbox = mailbox
        self.clock = clock
        self.maximumSampleAgeNanoseconds = maximumSampleAgeNanoseconds
    }

    @discardableResult
    public func poll(nowNanoseconds: UInt64? = nil) -> AudioFeatures? {
        guard let frame = collector.latestWindow(fftSize: analyzer.configuration.fftSize,
                                                  hopSize: analyzer.configuration.hopSize) else { return nil }
        let sampleNanoseconds = clock.nanoseconds(for: frame.timestamp)
        let now = nowNanoseconds ?? clock.nowNanoseconds()
        let age = sampleNanoseconds.flatMap { _ in
            clock.ageNanoseconds(of: frame.timestamp, nowNanoseconds: now)
        }
        let isFresh = frame.isFresh && age.map { $0 <= maximumSampleAgeNanoseconds } == true

        let timestampRegressed = if let previousTimestampNanoseconds, let sampleNanoseconds {
            sampleNanoseconds <= previousTimestampNanoseconds
        } else {
            false
        }
        if frame.isDiscontinuous || timestampRegressed {
            smoother.reset()
        }
        let elapsedNanoseconds: UInt64
        if let previousTimestampNanoseconds, let sampleNanoseconds,
           sampleNanoseconds > previousTimestampNanoseconds {
            elapsedNanoseconds = min(
                sampleNanoseconds - previousTimestampNanoseconds,
                maximumSampleAgeNanoseconds
            )
        } else {
            elapsedNanoseconds = AudioTiming.smoothingReferenceIntervalNanoseconds
        }
        previousTimestampNanoseconds = sampleNanoseconds

        let rawFeatures = analyzer.analyze(
            samples: frame.samples,
            timestamp: frame.timestamp,
            generation: frame.generation,
            isFresh: isFresh
        )
        _ = mailbox.publish(frame)
        return smoother.ingest(rawFeatures, elapsedNanoseconds: elapsedNanoseconds)
    }

    public func reset(generation: UInt64) {
        collector.reset(generation: generation)
        mailbox.reset(generation: generation)
        previousTimestampNanoseconds = nil
        smoother.reset()
    }
}
