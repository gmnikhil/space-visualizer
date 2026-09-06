import Foundation

public final class AudioFeaturePipeline: @unchecked Sendable {
    public let collector: PCMBufferCollector
    public let analyzer: AudioAnalyzer
    public let mailbox: AudioFrameMailbox
    private var smoother = FeatureSmoother(attack: 0.7, release: 0.2)

    public init(collector: PCMBufferCollector, analyzer: AudioAnalyzer, mailbox: AudioFrameMailbox = AudioFrameMailbox()) {
        self.collector = collector
        self.analyzer = analyzer
        self.mailbox = mailbox
    }

    @discardableResult
    public func poll() -> AudioFeatures? {
        guard let frame = collector.latestWindow(fftSize: analyzer.configuration.fftSize,
                                                  hopSize: analyzer.configuration.hopSize) else { return nil }
        let samples = frame.samples
        mailbox.publish(frame)
        let rawFeatures = analyzer.analyze(
            samples: samples,
            timestamp: frame.timestamp,
            generation: frame.generation
        )
        return smoother.ingest(rawFeatures)
    }

    public func reset(generation: UInt64) {
        collector.reset(generation: generation)
        mailbox.reset(generation: generation)
        smoother.reset()
    }
}
