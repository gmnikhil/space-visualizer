import XCTest
@testable import SpaceVisualizerCore

final class CaptureTelemetryTests: XCTestCase {
    func testRenderFailureIsDistinctFromNoCallback() {
        let telemetry = CaptureTelemetry()
        XCTAssertEqual(telemetry.snapshot().callbacks, 0)
        telemetry.record(frames: 512, status: -50, callbackAgeNanoseconds: 2_000)
        XCTAssertEqual(telemetry.snapshot().callbacks, 1)
        XCTAssertEqual(telemetry.snapshot().renderedFrames, 0)
        XCTAssertEqual(telemetry.snapshot().lastRenderStatus, -50)
        telemetry.record(frames: 512, status: 0, callbackAgeNanoseconds: 8_000)
        XCTAssertEqual(telemetry.snapshot().callbacks, 2)
        XCTAssertEqual(telemetry.snapshot().renderedFrames, 512)
        XCTAssertEqual(telemetry.snapshot().callbackAge.samples, 2)
        XCTAssertEqual(telemetry.snapshot().callbackAge.p50Nanoseconds, 5_000)
        XCTAssertEqual(telemetry.snapshot().callbackAge.p95Nanoseconds, 10_000)
    }
}
