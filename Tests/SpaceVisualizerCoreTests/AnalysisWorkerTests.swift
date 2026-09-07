import XCTest
import Combine
@testable import SpaceVisualizerCore

final class AnalysisWorkerTests: XCTestCase {
    func testWorkerProducesResultOffUIThreadAndStopClearsIt() {
        let collector = PCMBufferCollector(capacity: 64)
        let clock = TestAudioTimestampClock(now: 42)
        let pipeline = AudioFeaturePipeline(collector: collector, analyzer: AudioAnalyzer(
            configuration: AudioAnalyzerConfiguration(sampleRate: 48_000, channelCount: 1,
                                                      isInterleaved: true, fftSize: 8, hopSize: 2)), clock: clock)
        let worker = AnalysisWorker(pipeline: pipeline, clock: clock)
        let samples = [Float](repeating: 0.1, count: 8)
        samples.withUnsafeBufferPointer {
            _ = collector.accept(samples: $0, timestamp: 42, sampleRate: 48_000,
                                 channelCount: 1, generation: 1)
        }
        worker.start()
        defer { worker.stop() }
        let ready = expectation(description: "Worker produced audio features")
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline {
                if worker.snapshot() != nil { ready.fulfill(); return }
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
        wait(for: [ready], timeout: 2)
        worker.stop()
        XCTAssertNil(worker.snapshot())
    }

    func testSnapshotExpiresFromInputTimestampInsteadOfWorkerCompletionTime() {
        let collector = PCMBufferCollector(capacity: 64)
        let clock = TestAudioTimestampClock(now: 100_000_000)
        let pipeline = AudioFeaturePipeline(collector: collector, analyzer: AudioAnalyzer(
            configuration: AudioAnalyzerConfiguration(sampleRate: 48_000, channelCount: 1,
                                                      isInterleaved: true, fftSize: 8, hopSize: 2)),
                                            clock: clock)
        let samples = [Float](repeating: 0.1, count: 8)
        samples.withUnsafeBufferPointer {
            _ = collector.accept(samples: $0, timestamp: 100_000_000, sampleRate: 48_000,
                                 channelCount: 1, generation: 1)
        }
        let worker = AnalysisWorker(pipeline: pipeline, clock: clock)
        worker.start()
        defer { worker.stop() }

        let ready = expectation(description: "Fresh input published")
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline {
                if worker.snapshot() != nil { ready.fulfill(); return }
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
        wait(for: [ready], timeout: 2)
        let runningMetrics = worker.telemetry.snapshot()
        XCTAssertGreaterThan(runningMetrics.analysisDuration.samples, 0)
        XCTAssertGreaterThan(runningMetrics.mailboxAge.samples, 0)
        XCTAssertEqual(runningMetrics.workerStarts, 1)
        XCTAssertEqual(runningMetrics.activeWorkers, 1)

        clock.now = 351_000_000
        XCTAssertNil(worker.snapshot())
        worker.stop()
        XCTAssertEqual(worker.telemetry.snapshot().activeWorkers, 0)
    }

    func testWorkerPublishesOneStaleInvalidationWhenInputExpires() {
        let collector = PCMBufferCollector(capacity: 64)
        let clock = TestAudioTimestampClock(now: 100_000_000)
        let pipeline = AudioFeaturePipeline(collector: collector, analyzer: AudioAnalyzer(
            configuration: AudioAnalyzerConfiguration(sampleRate: 48_000, channelCount: 1,
                                                      isInterleaved: true, fftSize: 8, hopSize: 2)),
                                            clock: clock)
        let samples = [Float](repeating: 0.1, count: 8)
        samples.withUnsafeBufferPointer {
            _ = collector.accept(samples: $0, timestamp: 100_000_000, sampleRate: 48_000,
                                 channelCount: 1, generation: 1)
        }
        let staleExpectation = expectation(description: "Stale input invalidated")
        let featureLock = NSLock()
        var staleFeature: AudioFeatures?
        let worker = AnalysisWorker(pipeline: pipeline, onFeatures: { feature in
            guard !feature.isFresh else { return }
            featureLock.lock()
            staleFeature = feature
            featureLock.unlock()
            staleExpectation.fulfill()
        }, clock: clock)
        worker.start()
        defer { worker.stop() }

        let freshExpectation = expectation(description: "Fresh input published")
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline {
                if worker.snapshot() != nil { freshExpectation.fulfill(); return }
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
        wait(for: [freshExpectation], timeout: 2)
        clock.now = 351_000_000
        wait(for: [staleExpectation], timeout: 2)

        featureLock.lock()
        let result = staleFeature
        featureLock.unlock()
        XCTAssertFalse(result?.isFresh == true)
        XCTAssertEqual(result?.generation, 1)
    }

    func testVisualStoreDoesNotPublishRepeatedFrames() {
        let store = VisualFeatureStore()
        var updates = 0
        let observation = store.objectWillChange.sink { updates += 1 }
        store.update(.settled)
        store.update(.fixtureLive)
        store.update(.fixtureLive)
        XCTAssertEqual(updates, 1)
        store.update(.settled)
        XCTAssertEqual(updates, 2)
        withExtendedLifetime(observation) {}
    }
}
