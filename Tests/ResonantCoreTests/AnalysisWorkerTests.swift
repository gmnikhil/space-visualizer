import XCTest
import Combine
@testable import ResonantCore

final class AnalysisWorkerTests: XCTestCase {
    func testWorkerProducesResultOffUIThreadAndStopClearsIt() {
        let collector = PCMBufferCollector(capacity: 64)
        let pipeline = AudioFeaturePipeline(collector: collector, analyzer: AudioAnalyzer(
            configuration: AudioAnalyzerConfiguration(sampleRate: 48_000, channelCount: 1,
                                                      isInterleaved: true, fftSize: 8, hopSize: 2)))
        let worker = AnalysisWorker(pipeline: pipeline)
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
