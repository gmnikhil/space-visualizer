import XCTest
@testable import ResonantCore

final class AudioAnalysisTests: XCTestCase {
    func testRingBufferPreservesOrderAndDropsOldestWhenFull() {
        let buffer = AudioRingBuffer(capacity: 4)

        XCTAssertEqual(buffer.write([1, 2, 3]), 0)
        XCTAssertEqual(buffer.write([4, 5]), 1)
        XCTAssertEqual(buffer.read(maximumSamples: 8), [2, 3, 4, 5])
        XCTAssertEqual(buffer.read(maximumSamples: 8), [])
    }

    func testOverlappingWindowsRequireNewSamplesAndDropBacklog() {
        let buffer = AudioRingBuffer(capacity: 16)
        _ = buffer.write([1, 2, 3, 4])
        XCTAssertEqual(buffer.readLatestWindow(sampleCount: 4, retainingSamples: 2), [1, 2, 3, 4])
        XCTAssertEqual(buffer.readLatestWindow(sampleCount: 4, retainingSamples: 2), [])
        _ = buffer.write([5, 6])
        XCTAssertEqual(buffer.readLatestWindow(sampleCount: 4, retainingSamples: 2), [3, 4, 5, 6])
        _ = buffer.write([7, 8, 9, 10, 11, 12])
        XCTAssertEqual(buffer.readLatestWindow(sampleCount: 4, retainingSamples: 2), [9, 10, 11, 12])
        buffer.reset()
        XCTAssertEqual(buffer.count, 0)
    }

    func testLatestWindowDropsBacklogAndPreservesIncompleteFrames() {
        let buffer = AudioRingBuffer(capacity: 16)
        _ = buffer.write([1, 2, 3])
        XCTAssertEqual(buffer.readLatestWindow(sampleCount: 4), [])
        XCTAssertEqual(buffer.count, 3)
        _ = buffer.write([4, 5, 6, 7, 8])
        XCTAssertEqual(buffer.readLatestWindow(sampleCount: 4), [5, 6, 7, 8])
        XCTAssertEqual(buffer.count, 0)
    }

    func testRingBufferResetDiscardsPendingSamples() {
        let buffer = AudioRingBuffer(capacity: 4)
        _ = buffer.write([1, 2, 3])

        buffer.reset()

        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.read(maximumSamples: 4), [])
    }

    func testFramePreservesTimestampFormatGenerationAndFreshness() {
        let frame = AudioFrame(
            timestamp: 42,
            sampleRate: 44_100,
            channelCount: 2,
            generation: 7,
            samples: [0.1, -0.1],
            isFresh: true
        )
        let mailbox = AudioFrameMailbox()

        mailbox.publish(frame)

        XCTAssertEqual(mailbox.latest(), frame)
        XCTAssertEqual(mailbox.latest()?.generation, 7)
        XCTAssertEqual(mailbox.latest()?.sampleRate, 44_100)
        XCTAssertTrue(mailbox.latest()?.isFresh == true)
    }

    func testGenerationResetDropsOldFrame() {
        let mailbox = AudioFrameMailbox()
        mailbox.publish(AudioFrame.fixture)

        mailbox.reset(generation: 8)

        XCTAssertNil(mailbox.latest())
        XCTAssertEqual(mailbox.generation, 8)
    }

    func testAnalyzerSeparatesBassMidAndHighTones() {
        let analyzer = AudioAnalyzer(configuration: .fixture)
        let readings = [
            analyzer.analyze(samples: ToneFixture.samples(hz: 80), timestamp: 1, generation: 1),
            analyzer.analyze(samples: ToneFixture.samples(hz: 1_000), timestamp: 2, generation: 1),
            analyzer.analyze(samples: ToneFixture.samples(hz: 8_000), timestamp: 3, generation: 1)
        ]

        XCTAssertGreaterThan(readings[0].bass, readings[0].mids + 0.2)
        XCTAssertGreaterThan(readings[0].bass, readings[0].highs + 0.2)
        XCTAssertGreaterThan(readings[1].mids, readings[1].bass + 0.2)
        XCTAssertGreaterThan(readings[1].mids, readings[1].highs + 0.2)
        XCTAssertGreaterThan(readings[2].highs, readings[2].bass + 0.2)
        XCTAssertGreaterThan(readings[2].highs, readings[2].mids + 0.2)
        XCTAssertTrue(readings.allSatisfy { $0.isFresh && !$0.isSilent })
    }

    func testHighSampleRatesPreserveBandSeparation() {
        for rate in [96_000.0, 192_000.0] {
            let count = AudioAnalyzerConfiguration.windowSize(sampleRate: rate)
            let analyzer = AudioAnalyzer(configuration: AudioAnalyzerConfiguration(
                sampleRate: rate, channelCount: 1, isInterleaved: true, fftSize: count))
            for (index, frequency) in [80.0, 1_000.0, 8_000.0].enumerated() {
                let result = analyzer.analyze(samples: ToneFixture.samples(hz: frequency, sampleRate: rate, count: count),
                                              timestamp: 1, generation: 1)
                let bands = [result.bass, result.mids, result.highs]
                XCTAssertTrue(result.isFresh)
                for other in 0..<3 where other != index {
                    XCTAssertGreaterThan(bands[index], bands[other] + 0.2)
                }
            }
        }
    }

    func testAnalyzerTreatsSilenceAsSilentWithZeroEnergy() {
        let analyzer = AudioAnalyzer(configuration: .fixture)
        let result = analyzer.analyze(
            samples: Array(repeating: Float.zero, count: AudioAnalyzerConfiguration.fixture.fftSize),
            timestamp: 10,
            generation: 3
        )

        XCTAssertTrue(result.isFresh)
        XCTAssertTrue(result.isSilent)
        XCTAssertEqual(result.rms, 0, accuracy: 0.00001)
        XCTAssertEqual(result.bass, 0, accuracy: 0.00001)
        XCTAssertEqual(result.mids, 0, accuracy: 0.00001)
        XCTAssertEqual(result.highs, 0, accuracy: 0.00001)
    }

    func testAnalyzerRejectsShortInputAsStale() {
        let analyzer = AudioAnalyzer(configuration: .fixture)
        let result = analyzer.analyze(samples: [0, 0, 0], timestamp: 11, generation: 4)

        XCTAssertFalse(result.isFresh)
        XCTAssertTrue(result.isSilent)
        XCTAssertEqual(result.generation, 4)
    }

    func testAnalyzerPerformanceOnTheDiagnosticWindow() {
        let analyzer = AudioAnalyzer(configuration: .fixture)
        let samples = ToneFixture.samples(hz: 1_000)

        measure {
            _ = analyzer.analyze(samples: samples, timestamp: 1, generation: 1)
        }
    }

    func testPipelinePublishesSmoothedFeaturesAndResetsOnGenerationChange() {
        let collector = PCMBufferCollector(capacity: 4_096)
        let analyzer = AudioAnalyzer(configuration: .fixture)
        let pipeline = AudioFeaturePipeline(collector: collector, analyzer: analyzer)
        let samples = ToneFixture.samples(hz: 80)
        samples.withUnsafeBufferPointer { pointer in
            _ = collector.accept(
                samples: pointer,
                timestamp: 100,
                sampleRate: 48_000,
                channelCount: 1,
                generation: 1
            )
        }

        let features = pipeline.poll()

        XCTAssertNotNil(features)
        XCTAssertEqual(features?.generation, 1)
        XCTAssertTrue(features?.isFresh == true)
        XCTAssertGreaterThan(features?.bass ?? 0, 0)

        pipeline.reset(generation: 2)
        XCTAssertNil(pipeline.poll())
    }

    func testSmootherUsesAttackAndReleaseAndCanReset() {
        var smoother = FeatureSmoother(attack: 0.5, release: 0.1)
        let live = AudioFeatures.fixtureLive
        let silent = AudioFeatures.fixtureSilent

        let attacked = smoother.ingest(live)
        let released = smoother.ingest(silent)
        smoother.reset()

        XCTAssertGreaterThan(attacked.bass, 0)
        XCTAssertLessThan(attacked.bass, live.bass)
        XCTAssertGreaterThan(released.bass, 0)
        XCTAssertLessThan(released.bass, attacked.bass)
        XCTAssertEqual(smoother.current, .settled)
    }
}

private enum ToneFixture {
    static func samples(hz: Double, sampleRate: Double = 48_000, count: Int = AudioAnalyzerConfiguration.fixture.fftSize) -> [Float] {
        (0..<count).map { index in
            guard hz > 0 else { return 0 }
            return Float(sin(2 * Double.pi * hz * Double(index) / sampleRate) * 0.16)
        }
    }
}

private extension AudioAnalyzerConfiguration {
    static let fixture = AudioAnalyzerConfiguration(
        sampleRate: 48_000,
        channelCount: 1,
        isInterleaved: true,
        fftSize: 2_048,
        hopSize: 512,
        silenceThreshold: 0.0005
    )
}

private extension AudioFrame {
    static let fixture = AudioFrame(
        timestamp: 10,
        sampleRate: 48_000,
        channelCount: 2,
        generation: 7,
        samples: [0.25, -0.25],
        isFresh: true
    )
}
