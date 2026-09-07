import XCTest
@testable import SpaceVisualizerCore

final class DiagnosticEngineTests: XCTestCase {
    func testSubscriptionAttemptCannotBypassAnUnverifiedControl() {
        let engine = makeEngine()
        prepareLiveState(engine)
        engine.setPhase(.streamedSubscription)

        engine.recordAttempt(
            playbackAudible: true,
            expectedBand: "mids",
            measuredBand: "mids",
            controlVerified: true
        )

        XCTAssertEqual(engine.lastReport?.tests.last?.result, .inconclusive)
        XCTAssertFalse(engine.hasVerifiedControl)
    }

    func testSubscriptionAttemptUsesARecordedControlPass() {
        let engine = makeEngine()
        prepareLiveState(engine)

        engine.recordAttempt(
            playbackAudible: true,
            expectedBand: "bass",
            measuredBand: "bass",
            controlVerified: true
        )
        XCTAssertTrue(engine.hasVerifiedControl)

        engine.setPhase(.streamedSubscription)
        engine.recordAttempt(
            playbackAudible: true,
            expectedBand: "mids",
            measuredBand: "mids",
            controlVerified: false
        )

        XCTAssertEqual(engine.lastReport?.tests.map(\.result), [.pass, .pass])
    }

    private func makeEngine() -> DiagnosticEngine {
        DiagnosticEngine(
            metadataQuery: StaticMusicQuery(),
            routeProvider: StaticRouteProvider(),
            permissionProvider: AuthorizedPermissionProvider()
        )
    }

    private func prepareLiveState(_ engine: DiagnosticEngine) {
        engine.permission.updateStatus(.authorized)
        engine.apply(.captureStarted(route: .fixtureSpeaker, format: .fixtureStereo))
        engine.apply(.features(.fixtureLive))
    }
}

private final class StaticMusicQuery: MusicQuerying {
    func query() throws -> RawMusicSnapshot { .unknown }
}

private final class StaticRouteProvider: AudioRouteProviding {
    func availableRoutes() throws -> [AudioRouteFacts] { [.fixtureSpeaker] }
}

private final class AuthorizedPermissionProvider: AudioPermissionProviding {
    let status: AudioPermissionStatus = .authorized
    func requestPermission() -> AudioPermissionStatus { status }
}
