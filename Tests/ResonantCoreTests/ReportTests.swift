import XCTest
@testable import ResonantCore

final class ReportTests: XCTestCase {
    func testControlFailureIsInconclusiveRatherThanAContentConclusion() {
        let evidence = TestEvidence.fixtureControlFailure

        let result = FeasibilityClassifier.classify(evidence)

        XCTAssertEqual(result, .inconclusive)
        XCTAssertTrue(FeasibilityClassifier.explanation(for: result).localizedCaseInsensitiveContains("control"))
        XCTAssertFalse(FeasibilityClassifier.explanation(for: result).localizedCaseInsensitiveContains("DRM detected"))
    }

    func testCorrelatedSubscriptionPlaybackCanPass() {
        let evidence = TestEvidence.fixtureSubscriptionPass

        XCTAssertEqual(FeasibilityClassifier.classify(evidence), .pass)
    }

    func testDownloadedSubscriptionUsesTheSameCorrelationRule() {
        var evidence = TestEvidence.fixtureSubscriptionPass
        evidence.phase = .downloadedSubscription

        XCTAssertEqual(FeasibilityClassifier.classify(evidence), .pass)
    }

    func testBandMismatchCannotBecomeAFalsePass() {
        var evidence = TestEvidence.fixtureSubscriptionPass
        evidence.measuredBand = "highs"

        XCTAssertEqual(FeasibilityClassifier.classify(evidence), .inconclusive)
    }

    func testMetadataUnavailableDoesNotInvalidateCorrelatedAudio() {
        var evidence = TestEvidence.fixtureSubscriptionPass
        evidence.metadataAvailable = false

        XCTAssertEqual(FeasibilityClassifier.classify(evidence), .pass)
    }

    func testPermissionOrRouteFailuresRemainInconclusive() {
        var permissionFailure = TestEvidence.fixtureSubscriptionPass
        permissionFailure.systemAudioPermission = AudioPermissionStatus.denied.rawValue
        var routeFailure = TestEvidence.fixtureSubscriptionPass
        routeFailure.route = nil

        XCTAssertEqual(FeasibilityClassifier.classify(permissionFailure), .inconclusive)
        XCTAssertEqual(FeasibilityClassifier.classify(routeFailure), .inconclusive)
    }

    func testAudibleSubscriptionWithoutSamplesDoesNotClaimDRM() {
        let evidence = TestEvidence.fixtureSubscriptionUnavailable

        let result = FeasibilityClassifier.classify(evidence)

        XCTAssertTrue(result == .fail || result == .inconclusive)
        XCTAssertFalse(FeasibilityClassifier.explanation(for: result).localizedCaseInsensitiveContains("DRM detected"))
    }

    func testReportContainsEvidenceButNeverPcmOrArtwork() throws {
        let report = DiagnosticReport.fixture
        let data = try JSONEncoder().encode(report)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("Built-in Speakers"))
        XCTAssertTrue(json.contains("streamed-subscription"))
        XCTAssertFalse(json.contains("pcm"))
        XCTAssertFalse(json.contains("artwork"))
        XCTAssertFalse(json.contains("audioRecording"))
    }
}
