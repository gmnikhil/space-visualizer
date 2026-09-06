import XCTest
@testable import ResonantCore

final class CaptureTelemetryTests: XCTestCase {
    func testRenderFailureIsDistinctFromNoCallback() {
        let telemetry = CaptureTelemetry()
        XCTAssertEqual(telemetry.snapshot().callbacks, 0)
        telemetry.record(frames: 512, status: -50)
        XCTAssertEqual(telemetry.snapshot().callbacks, 1)
        XCTAssertEqual(telemetry.snapshot().renderedFrames, 0)
        XCTAssertEqual(telemetry.snapshot().lastRenderStatus, -50)
        telemetry.record(frames: 512, status: 0)
        XCTAssertEqual(telemetry.snapshot().callbacks, 2)
        XCTAssertEqual(telemetry.snapshot().renderedFrames, 512)
    }
}
