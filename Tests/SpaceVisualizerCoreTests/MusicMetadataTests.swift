import XCTest
@testable import SpaceVisualizerCore

final class MusicMetadataTests: XCTestCase {
    func testNormalizerTrimsTextAndMarksInvalidNumbersUnknown() {
        let raw = RawMusicSnapshot(
            title: "  Control Study  ",
            artist: " Fixture Artist ",
            album: " Diagnostics ",
            playbackState: .playing,
            position: .infinity,
            duration: -1,
            artworkAvailable: true
        )

        let snapshot = MusicMetadataNormalizer.normalize(raw)

        XCTAssertEqual(snapshot.title, "Control Study")
        XCTAssertEqual(snapshot.artist, "Fixture Artist")
        XCTAssertEqual(snapshot.album, "Diagnostics")
        XCTAssertNil(snapshot.position)
        XCTAssertNil(snapshot.duration)
        XCTAssertTrue(snapshot.artworkAvailable)
    }

    func testNormalizerPreservesUnknownTrackFields() {
        let snapshot = MusicMetadataNormalizer.normalize(.unknown)

        XCTAssertNil(snapshot.title)
        XCTAssertNil(snapshot.artist)
        XCTAssertNil(snapshot.album)
        XCTAssertNil(snapshot.position)
        XCTAssertNil(snapshot.duration)
        XCTAssertEqual(snapshot.playbackState, .unknown)
    }

    func testCoordinatorMapsAutomationDenialToPermissionRequired() {
        let query = FakeMusicQuery()
        query.response = .failure(MusicBridgeError.automationDenied)
        let coordinator = MusicMetadataCoordinator(query: query)

        let result = coordinator.refresh()

        XCTAssertEqual(result, .permissionRequired("Music automation permission is required."))
        XCTAssertEqual(coordinator.health, .permissionRequired)
        XCTAssertNil(coordinator.snapshot)
    }

    func testCoordinatorMapsMusicFailureToUnavailable() {
        let query = FakeMusicQuery()
        query.response = .failure(MusicBridgeError.musicUnavailable)
        let coordinator = MusicMetadataCoordinator(query: query)

        let result = coordinator.refresh()

        XCTAssertEqual(result, .unavailable("Music is not available."))
        XCTAssertEqual(coordinator.health, .unavailable)
    }

    func testRefreshIsBoundedAndDoesNotQueryBeforeTheInterval() {
        let query = FakeMusicQuery()
        query.response = .success(.fixtureRaw)
        let clock = FakeClock()
        let coordinator = MusicMetadataCoordinator(
            query: query,
            clock: clock,
            minimumRefreshIntervalNanoseconds: 500_000_000
        )

        XCTAssertEqual(coordinator.refresh(), .available(.fixtureTrack))
        XCTAssertEqual(query.queryCount, 1)

        clock.now = 100_000_000
        XCTAssertEqual(coordinator.refresh(), .throttled)
        XCTAssertEqual(query.queryCount, 1)

        clock.now = 500_000_000
        XCTAssertEqual(coordinator.refresh(), .available(.fixtureTrack))
        XCTAssertEqual(query.queryCount, 2)
    }

    func testAutomationDenialWaitsForAnExplicitForcedRetry() {
        let query = FakeMusicQuery()
        query.response = .failure(MusicBridgeError.automationDenied)
        let clock = FakeClock()
        let coordinator = MusicMetadataCoordinator(query: query, clock: clock)

        _ = coordinator.refresh()
        clock.now = 2_000_000_000
        XCTAssertEqual(coordinator.refresh(), .throttled)
        XCTAssertEqual(query.queryCount, 1)

        query.response = .success(.fixtureRaw)
        XCTAssertEqual(coordinator.refresh(force: true), .available(.fixtureTrack))
        XCTAssertEqual(query.queryCount, 2)
    }

    func testStopDisablesAutomaticMetadataPolling() {
        let query = FakeMusicQuery()
        query.response = .success(.fixtureRaw)
        let engine = DiagnosticEngine(metadataQuery: query, routeProvider: EmptyRouteProvider(),
                                      permissionProvider: MetadataPermissionProvider())
        engine.beginMetadataObservation()
        engine.stop()
        let count = query.queryCount
        for _ in 0..<100 { _ = engine.refreshMetadata() }
        XCTAssertEqual(query.queryCount, count)
        XCTAssertFalse(engine.isMetadataObservationEnabled)
        XCTAssertFalse(engine.isCapturing)
    }

    func testIdenticalMetadataDoesNotGrowEventLog() {
        let query = FakeMusicQuery()
        query.response = .success(.fixtureRaw)
        let engine = DiagnosticEngine(metadataQuery: query, routeProvider: EmptyRouteProvider(),
                                      permissionProvider: MetadataPermissionProvider())
        engine.beginMetadataObservation()
        let count = engine.events.count
        for _ in 0..<10 { _ = engine.refreshMetadata(force: true) }
        XCTAssertEqual(engine.events.count, count)
        engine.stop()
    }

    func testEngineDoesNotRequestMetadataUntilUserStartsObservation() {
        let query = FakeMusicQuery()
        query.response = .success(.fixtureRaw)
        let engine = DiagnosticEngine(
            metadataQuery: query,
            routeProvider: EmptyRouteProvider(),
            permissionProvider: MetadataPermissionProvider()
        )

        _ = engine.refreshMetadata()
        XCTAssertEqual(query.queryCount, 0)
        XCTAssertFalse(engine.isMetadataObservationEnabled)

        engine.beginMetadataObservation()
        XCTAssertEqual(query.queryCount, 1)
        XCTAssertTrue(engine.isMetadataObservationEnabled)
    }

    func testMetadataRefreshCanFailWhileAudioStateRemainsLive() {
        let query = FakeMusicQuery()
        query.response = .failure(MusicBridgeError.automationDenied)
        let coordinator = MusicMetadataCoordinator(query: query)
        var machine = DiagnosticStateMachine()
        machine.transition(.captureStarted(route: .fixtureSpeaker, format: .fixtureStereo))
        machine.transition(.features(.fixtureLive))

        _ = coordinator.refresh()
        machine.transition(.metadataUnavailable("Automation denied"))

        XCTAssertEqual(machine.state.audioHealth, .live)
        XCTAssertEqual(coordinator.health, .permissionRequired)
    }
}

private final class EmptyRouteProvider: AudioRouteProviding {
    func availableRoutes() throws -> [AudioRouteFacts] { [] }
}

private final class MetadataPermissionProvider: AudioPermissionProviding {
    let status: AudioPermissionStatus = .authorized
    func requestPermission() -> AudioPermissionStatus { status }
}

