import XCTest
@testable import SpaceVisualizerCore

final class DiagnosticStateMachineTests: XCTestCase {
    func testMetadataFailureDoesNotInvalidateLiveAudio() {
        var machine = DiagnosticStateMachine()
        machine.transition(.captureStarted(route: .fixtureSpeaker, format: .fixtureStereo))
        machine.transition(.features(.fixtureLive))
        machine.transition(.metadataUnavailable("Automation denied"))

        XCTAssertEqual(machine.state.audioHealth, .live)
        XCTAssertEqual(machine.state.metadataHealth, .unavailable)
        XCTAssertEqual(machine.state.captureState, .active)
        XCTAssertEqual(machine.state.message, "Automation denied")
    }

    func testStartRequestsAudioPermissionWithoutInventingMetadata() {
        var machine = DiagnosticStateMachine()
        machine.transition(.start)

        XCTAssertEqual(machine.state.captureState, .permissionRequired)
        XCTAssertEqual(machine.state.audioHealth, .permissionRequired)
        XCTAssertEqual(machine.state.metadataHealth, .unknown)
        XCTAssertNil(machine.state.track)
    }

    func testMissingAudioFrameIsNotReportedAsLive() {
        var machine = DiagnosticStateMachine()
        machine.transition(.captureStarted(route: .fixtureSpeaker, format: .fixtureStereo))
        machine.transition(.captureNoSamples)

        XCTAssertEqual(machine.state.captureState, .active)
        XCTAssertEqual(machine.state.audioHealth, .unavailable)
        XCTAssertNil(machine.state.latestFeatures)
        XCTAssertTrue(machine.state.message.contains("no complete fresh audio frame"))
        XCTAssertFalse(machine.state.isLiveSignal)
    }

    func testSilenceSettlesWithoutAFalseLiveState() {
        var machine = DiagnosticStateMachine()
        machine.transition(.captureStarted(route: .fixtureSpeaker, format: .fixtureStereo))
        machine.transition(.features(.fixtureSilent))

        XCTAssertEqual(machine.state.audioHealth, .silent)
        XCTAssertEqual(machine.state.captureState, .active)
        XCTAssertFalse(machine.state.isLiveSignal)
    }

    func testRouteChangeInvalidatesOldFeatures() {
        var machine = DiagnosticStateMachine()
        machine.transition(.captureStarted(route: .fixtureSpeaker, format: .fixtureStereo))
        machine.transition(.features(.fixtureLive))
        machine.transition(.routeChanged("AirPlay"))

        XCTAssertEqual(machine.state.captureState, .reconnecting)
        XCTAssertEqual(machine.state.audioHealth, .reconnecting)
        XCTAssertNil(machine.state.latestFeatures)
        XCTAssertEqual(machine.state.message, "AirPlay")
    }

    func testStopIsIdempotentAndDoesNotRepresentPlaybackControl() {
        var machine = DiagnosticStateMachine()
        machine.transition(.start)
        machine.transition(.stopped)
        machine.transition(.stopped)

        XCTAssertEqual(machine.state.captureState, .stopped)
        XCTAssertEqual(machine.state.audioHealth, .stopped)
        XCTAssertNil(machine.state.latestFeatures)
        XCTAssertEqual(machine.state.playbackCommandsIssued, 0)
    }

    func testCaptureFailurePreservesMetadataSnapshotButClearsAudio() {
        var machine = DiagnosticStateMachine()
        machine.transition(.metadataAvailable(.fixtureTrack))
        machine.transition(.captureStarted(route: .fixtureSpeaker, format: .fixtureStereo))
        machine.transition(.features(.fixtureLive))
        machine.transition(.captureFailed("tap unavailable"))

        XCTAssertEqual(machine.state.metadataHealth, .available)
        XCTAssertEqual(machine.state.track, .fixtureTrack)
        XCTAssertEqual(machine.state.audioHealth, .failed)
        XCTAssertNil(machine.state.latestFeatures)
    }
}
