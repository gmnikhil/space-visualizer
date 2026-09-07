import XCTest
@testable import SpaceVisualizerCore

final class DisplayCadenceTests: XCTestCase {
    func testCadenceRequestsUpTo120ButFollowsA60HzDisplay() {
        XCTAssertEqual(DisplayCadencePolicy.preferredFramesPerSecond(displayMaximum: nil), 120)
        XCTAssertEqual(DisplayCadencePolicy.preferredFramesPerSecond(displayMaximum: 120), 120)
        XCTAssertEqual(DisplayCadencePolicy.preferredFramesPerSecond(displayMaximum: 60), 60)
        XCTAssertEqual(DisplayCadencePolicy.preferredFramesPerSecond(displayMaximum: 30), 30)
    }

    func testDiagnosticUpdatesAreCappedAtFourPerSecond() {
        var limiter = DiagnosticUpdateLimiter()

        XCTAssertTrue(limiter.shouldPublish(at: 0))
        XCTAssertFalse(limiter.shouldPublish(at: 249_999_999))
        XCTAssertTrue(limiter.shouldPublish(at: 250_000_000))
        XCTAssertFalse(limiter.shouldPublish(at: 400_000_000))
        XCTAssertTrue(limiter.shouldPublish(at: 500_000_000))
    }

    func testDisplayTelemetryRemainsBoundedAndReportsPercentiles() {
        let telemetry = DisplayFrameTelemetry()
        telemetry.recordFrame(workNanoseconds: 10_000)
        telemetry.recordFrame(workNanoseconds: 100_000)

        let summary = telemetry.snapshot().frameWork
        XCTAssertEqual(summary.samples, 2)
        XCTAssertNotNil(summary.p50Nanoseconds)
        XCTAssertNotNil(summary.p95Nanoseconds)
    }

    func testLatestFeatureMailboxDeduplicatesIdenticalPublication() {
        let mailbox = LatestAudioFeatures()
        let feature = AudioFeatures.fixtureLive

        mailbox.update(feature)
        mailbox.update(feature)

        XCTAssertEqual(mailbox.publicationCount, 1)
        XCTAssertEqual(mailbox.snapshot(), feature)
    }
}
