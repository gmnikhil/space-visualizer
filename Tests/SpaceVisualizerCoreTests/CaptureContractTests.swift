import XCTest
@testable import SpaceVisualizerCore

final class CaptureContractTests: XCTestCase {
    func testDeniedPermissionDoesNotStartCaptureAndOffersRecovery() {
        let permission = FakeAudioPermissionProvider(status: .denied)
        let resource = FakeCaptureResources()
        let coordinator = AudioPermissionCoordinator(provider: permission)

        let result = coordinator.ensurePermission()

        XCTAssertEqual(result, .denied)
        XCTAssertEqual(resource.starts, 0)
        XCTAssertTrue(coordinator.recoveryAction.contains("Privacy"))
    }

    func testMusicProcessTapPolicyIsPrivateTargetedAndNonMuting() {
        let policy = ProcessTapPolicy.music(routeID: "speaker-uid")

        XCTAssertEqual(policy.targetBundleIdentifier, "com.apple.Music")
        XCTAssertEqual(policy.routeID, "speaker-uid")
        XCTAssertTrue(policy.isPrivate)
        XCTAssertFalse(policy.isExclusive)
        XCTAssertTrue(policy.isMixdown)
        XCTAssertFalse(policy.isMono)
        XCTAssertTrue(policy.capturesOnlyTargetProcess)
        XCTAssertTrue(policy.leavesPlaybackUnmuted)
    }

    func testAuthorizedPermissionCanBeUsedWithoutRequestingMicrophone() {
        let permission = FakeAudioPermissionProvider(status: .authorized)
        let coordinator = AudioPermissionCoordinator(provider: permission)

        XCTAssertEqual(coordinator.ensurePermission(), .authorized)
        XCTAssertEqual(permission.requestCount, 0)
        XCTAssertFalse(coordinator.requestsMicrophone)
    }

    func testRouteResolverUsesTheOneActiveRouteAndRequiresExplicitSelectionWhenActiveSourcesAreAmbiguous() throws {
        let activeProvider = FakeAudioRouteProvider(routes: [.fixtureSpeaker, .fixtureAirPlay])
        let activeResolver = AudioRouteResolver(provider: activeProvider)
        XCTAssertEqual(activeResolver.resolve(preferredID: nil), .selected(.fixtureSpeaker))

        let ambiguousProvider = FakeAudioRouteProvider(routes: [.fixtureSpeaker, .fixtureActiveAirPlay])
        let ambiguousResolver = AudioRouteResolver(provider: ambiguousProvider)
        XCTAssertEqual(ambiguousResolver.resolve(preferredID: nil), .ambiguous(["Built-in Speakers", "Living Room AirPlay"]))
        XCTAssertEqual(ambiguousResolver.resolve(preferredID: "fixture-speaker"), .selected(.fixtureSpeaker))
    }

    func testRouteResolverReportsMissingRouteInsteadOfFallingBackToAllAudio() {
        let provider = FakeAudioRouteProvider(routes: [.fixtureSpeaker])
        let resolver = AudioRouteResolver(provider: provider)

        XCTAssertEqual(resolver.resolve(preferredID: "missing"), .unavailable("The selected audio route is unavailable."))
    }

    func testCaptureSessionStopsAndDestroysResourcesExactlyOnce() throws {
        let resource = FakeCaptureResources()
        let session = CaptureSession(resource: resource)

        try session.start()
        try session.start()
        session.stop()
        session.stop()

        XCTAssertEqual(resource.starts, 1)
        XCTAssertEqual(resource.stops, 1)
        XCTAssertEqual(resource.destroys, 1)
        XCTAssertFalse(session.isRunning)
    }

    func testCaptureSessionDestroysResourcesAfterStartFailure() {
        let resource = FakeCaptureResources()
        resource.startError = FixtureError()
        let session = CaptureSession(resource: resource)

        XCTAssertThrowsError(try session.start())
        session.stop()

        XCTAssertEqual(resource.starts, 1)
        XCTAssertEqual(resource.stops, 1)
        XCTAssertEqual(resource.destroys, 1)
        XCTAssertFalse(session.isRunning)
    }

    func testStreamGenerationInvalidatesStaleFramesOnRouteChange() {
        let stream = StreamGenerationController()
        let first = stream.current

        stream.routeChanged()

        XCTAssertNotEqual(stream.current, first)
        XCTAssertFalse(stream.accepts(first))
        XCTAssertTrue(stream.accepts(stream.current))
        XCTAssertTrue(stream.didInvalidateSamples)
    }
}

private final class FakeAudioPermissionProvider: AudioPermissionProviding {
    var status: AudioPermissionStatus
    private(set) var requestCount = 0

    init(status: AudioPermissionStatus) { self.status = status }

    func requestPermission() -> AudioPermissionStatus {
        requestCount += 1
        return status
    }
}

private final class FakeAudioRouteProvider: AudioRouteProviding {
    let routes: [AudioRouteFacts]
    init(routes: [AudioRouteFacts]) { self.routes = routes }
    func availableRoutes() throws -> [AudioRouteFacts] { routes }
}

private extension AudioRouteFacts {
    static let fixtureAirPlay = AudioRouteFacts(
        id: "fixture-airplay",
        name: "Living Room AirPlay",
        kind: .airPlay,
        isActive: false,
        sampleRate: 44_100,
        channelCount: 2
    )

    static let fixtureActiveAirPlay = AudioRouteFacts(
        id: "fixture-airplay",
        name: "Living Room AirPlay",
        kind: .airPlay,
        isActive: true,
        sampleRate: 44_100,
        channelCount: 2
    )
}
