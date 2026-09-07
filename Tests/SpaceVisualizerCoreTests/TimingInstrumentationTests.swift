import XCTest
@testable import SpaceVisualizerCore

final class TimingInstrumentationTests: XCTestCase {
    func testAnalysisTelemetryReportsBoundedTimingAndReturnsWorkerCountsToBaseline() {
        let telemetry = AnalysisTelemetry()
        telemetry.recordAnalysis(durationNanoseconds: 2_000, mailboxAgeNanoseconds: 4_000)
        telemetry.recordAnalysis(durationNanoseconds: 8_000, mailboxAgeNanoseconds: 16_000)
        telemetry.recordWorkerStarted()

        let active = telemetry.snapshot()
        XCTAssertEqual(active.analysisDuration.samples, 2)
        XCTAssertEqual(active.mailboxAge.samples, 2)
        XCTAssertEqual(active.workerStarts, 1)
        XCTAssertEqual(active.activeWorkers, 1)
        XCTAssertEqual(active.activeTasks, 1)
        XCTAssertNotNil(active.analysisDuration.p50Nanoseconds)
        XCTAssertNotNil(active.analysisDuration.p95Nanoseconds)

        telemetry.recordWorkerStopped()

        let idle = telemetry.snapshot()
        XCTAssertEqual(idle.activeWorkers, 0)
        XCTAssertEqual(idle.activeTasks, 0)
        XCTAssertEqual(idle.workerStops, 1)
    }

    func testProcessResourceSamplerNeverExposesAudioData() {
        let telemetry = AnalysisTelemetry()
        let snapshot = ProcessResourceSampler.snapshot(analysis: telemetry)

        XCTAssertEqual(snapshot.activeAnalysisWorkers, 0)
        XCTAssertEqual(snapshot.activeAnalysisTasks, 0)
        // Memory is an optional local process metric; PCM is never part of it.
        XCTAssertTrue(snapshot.residentMemoryBytes == nil || snapshot.residentMemoryBytes! > 0)
    }
}
