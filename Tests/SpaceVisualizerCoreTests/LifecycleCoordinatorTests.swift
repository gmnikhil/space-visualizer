import XCTest
@testable import SpaceVisualizerCore

final class LifecycleCoordinatorTests: XCTestCase {
    func testOnboardingDoesNotPromptPollOrOwnRuntimeResources() {
        let harness = LifecycleHarness()
        harness.coordinator.openWindow()

        XCTAssertEqual(harness.coordinator.state, .onboarding)
        XCTAssertEqual(harness.permissions.automationRequests, 0)
        XCTAssertEqual(harness.permissions.systemAudioRequests, 0)
        XCTAssertEqual(harness.query.queryCount, 0)
        XCTAssertFalse(harness.coordinator.hasIdleTimer)
        XCTAssertFalse(harness.coordinator.hasActiveWatchdog)
        XCTAssertEqual(harness.factory.creationCount, 0)
    }

    func testConsentTransitionsToWaitingAndPerformsOneInitialCheck() {
        let harness = LifecycleHarness()
        harness.coordinator.openWindow()
        harness.coordinator.enableAutomaticFollowing()

        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertTrue(harness.coordinator.consentIntent)
        XCTAssertEqual(harness.permissions.automationRequests, 1)
        XCTAssertEqual(harness.permissions.systemAudioRequests, 1)
        XCTAssertEqual(harness.query.queryCount, 1)
        XCTAssertTrue(harness.coordinator.hasIdleTimer)
        XCTAssertFalse(harness.coordinator.hasActiveWatchdog)
        XCTAssertEqual(harness.factory.creationCount, 0)
    }

    func testPausedMusicStaysStaticWithoutCaptureResources() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.query.complete(.success(.paused))

        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertEqual(harness.factory.creationCount, 0)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
        XCTAssertTrue(harness.coordinator.hasIdleTimer)
        XCTAssertFalse(harness.coordinator.hasActiveWatchdog)
    }

    func testPlayingMusicStartsExactlyOneSessionAndFreshSilenceIsNotPause() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.query.complete(.success(.playing))
        XCTAssertEqual(harness.coordinator.state, .starting)
        XCTAssertFalse(harness.coordinator.hasIdleTimer)
        XCTAssertTrue(harness.coordinator.hasActiveWatchdog)
        XCTAssertEqual(harness.factory.creationCount, 1)

        harness.factory.completeSuccess()
        XCTAssertEqual(harness.coordinator.activeSessionCount, 1)
        harness.coordinator.receiveAudio(.fixtureSilent.withGeneration(harness.coordinator.generation))

        XCTAssertEqual(harness.coordinator.state, .silent)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 1)
        XCTAssertTrue(harness.coordinator.hasActiveWatchdog)
    }

    func testHiddenWindowTearsDownExpensiveWorkAndReopenStartsFreshCheck() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.query.complete(.success(.playing))
        harness.factory.completeSuccess()
        harness.coordinator.receiveAudio(.fixtureLive.withGeneration(harness.coordinator.generation))

        harness.coordinator.setWindowVisible(false)

        XCTAssertEqual(harness.coordinator.state, .suspended)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
        XCTAssertFalse(harness.coordinator.hasIdleTimer)
        XCTAssertFalse(harness.coordinator.hasActiveWatchdog)
        XCTAssertEqual(harness.capture.stopCount, 1)
        XCTAssertEqual(harness.capture.destroyCount, 1)

        let checksBeforeReopen = harness.query.queryCount
        harness.coordinator.openWindow()
        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertEqual(harness.query.queryCount, checksBeforeReopen + 1)
    }

    func testRedundantVisibleEventsDoNotRestartActiveCapture() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.query.complete(.success(.playing))
        harness.factory.completeSuccess()
        harness.coordinator.receiveAudio(.fixtureLive.withGeneration(harness.coordinator.generation))
        let queries = harness.query.queryCount
        let creations = harness.factory.creationCount

        // A focus/window notification may report visible again. It must not
        // restart a live session or create a second watchdog/query.
        harness.coordinator.setWindowVisible(true)

        XCTAssertEqual(harness.coordinator.state, .visualizing)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 1)
        XCTAssertEqual(harness.query.queryCount, queries)
        XCTAssertEqual(harness.factory.creationCount, creations)
    }

    func testDeniedPermissionBlocksWithoutRepeatedPromptsOrPolling() {
        let harness = LifecycleHarness()
        harness.permissions.permissions = .init(automation: .denied, systemAudio: .authorized)
        harness.coordinator.openWindow()
        harness.coordinator.enableAutomaticFollowing()

        XCTAssertEqual(harness.coordinator.state, .permissionBlocked)
        XCTAssertEqual(harness.query.queryCount, 0)
        XCTAssertFalse(harness.coordinator.hasIdleTimer)
        XCTAssertEqual(harness.permissions.automationRequests, 1)

        harness.scheduler.advance(by: 60_000_000_000)
        XCTAssertEqual(harness.permissions.automationRequests, 1)
        XCTAssertEqual(harness.query.queryCount, 0)
    }

    func testFailedSessionRequiresExplicitRetryAndLateResourceIsDestroyed() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.query.complete(.success(.playing))
        XCTAssertEqual(harness.coordinator.state, .starting)

        harness.coordinator.closeWindow()
        harness.factory.completeSuccess()

        XCTAssertEqual(harness.coordinator.state, .suspended)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
        XCTAssertEqual(harness.capture.destroyCount, 1)
        XCTAssertFalse(harness.coordinator.hasIdleTimer)

        harness.coordinator.openWindow()
        XCTAssertEqual(harness.coordinator.state, .waiting)
        harness.query.complete(.success(.playing))
        harness.factory.nextStartError = FixtureError()
        harness.factory.completeFailure()
        XCTAssertEqual(harness.coordinator.state, .failed)
        XCTAssertFalse(harness.coordinator.hasIdleTimer)
    }

    func testQuitIsTerminalAndInvalidatesLatePlaybackAndSessionCompletions() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.query.complete(.success(.playing))
        harness.coordinator.quit()
        harness.query.complete(.success(.playing))
        harness.factory.completeSuccess()

        XCTAssertEqual(harness.coordinator.state, .terminated)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
        XCTAssertFalse(harness.coordinator.hasIdleTimer)
        XCTAssertFalse(harness.coordinator.hasActiveWatchdog)
        XCTAssertEqual(harness.factory.creationCount, 1)
        XCTAssertEqual(harness.capture.destroyCount, 1)
    }

    func testIdleChecksUseOneFiveSecondIntervalWithoutCatchUpOrOverlap() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        XCTAssertEqual(harness.scheduler.scheduledDelays, [
            5_000_000_000,
            SpaceVisualizerLifecycleCoordinator.playbackQueryTimeoutNanoseconds
        ])

        harness.query.complete(.success(.paused))
        harness.scheduler.advance(by: 4_999_999_999)
        XCTAssertEqual(harness.query.queryCount, 1)
        harness.scheduler.advance(by: 1)
        XCTAssertEqual(harness.query.queryCount, 2)

        // The five-second query is deliberately unresolved. A missed timer
        // tick cannot create a second query or a catch-up backlog.
        harness.scheduler.advance(by: 5_000_000_000)
        XCTAssertEqual(harness.query.queryCount, 2)

        harness.query.complete(.success(.paused))
        harness.scheduler.advance(by: 5_000_000_000)
        XCTAssertEqual(harness.query.queryCount, 3)
        XCTAssertEqual(harness.scheduler.scheduledDelays.filter { $0 == 5_000_000_000 }.count, 1)
    }

    func testStalledIdleQueryTimesOutAndNextPollRecoversDespiteLateCallback() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        let expiredToken = harness.query.tokens[0]

        harness.scheduler.advance(by: SpaceVisualizerLifecycleCoordinator.playbackQueryTimeoutNanoseconds)
        XCTAssertTrue(expiredToken.isCancelled)
        XCTAssertFalse(harness.coordinator.isQueryInFlight)
        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertEqual(harness.coordinator.message, "Music playback check timed out.")
        XCTAssertEqual(harness.scheduler.activeHandleCount, 1)

        harness.scheduler.advance(to: 5_000_000_000)
        XCTAssertEqual(harness.query.queryCount, 2)
        XCTAssertTrue(harness.coordinator.isQueryInFlight)

        // The expired provider responds after its replacement has started.
        harness.query.complete(.denied("Obsolete permission error"))
        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertTrue(harness.coordinator.isQueryInFlight)
        harness.query.complete(.success(.playing))
        harness.factory.completeSuccess()
        harness.coordinator.receiveAudio(.fixtureLive.withGeneration(harness.coordinator.generation))
        XCTAssertEqual(harness.coordinator.state, .visualizing)
        XCTAssertFalse(harness.coordinator.isQueryInFlight)
    }

    func testStalledActiveQueryReturnsToPollingAndRecovers() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.query.complete(.success(.playing))
        harness.factory.completeSuccess()
        harness.coordinator.receiveAudio(.fixtureLive.withGeneration(harness.coordinator.generation))
        harness.scheduler.advance(by: 2_000_000_000)

        harness.scheduler.advance(by: SpaceVisualizerLifecycleCoordinator.playbackQueryTimeoutNanoseconds)
        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertTrue(harness.query.tokens[1].isCancelled)
        XCTAssertFalse(harness.coordinator.isQueryInFlight)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
        XCTAssertTrue(harness.coordinator.hasIdleTimer)

        harness.query.complete(.success(.paused)) // Obsolete result.
        harness.scheduler.advance(by: 5_000_000_000)
        harness.query.complete(.success(.playing))
        harness.factory.completeSuccess()
        harness.coordinator.receiveAudio(.fixtureLive.withGeneration(harness.coordinator.generation))
        XCTAssertEqual(harness.coordinator.state, .visualizing)
        XCTAssertEqual(harness.factory.creationCount, 2)
    }

    func testTimeoutRetiresQueryBeforeSynchronousCancellationCallback() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.query.tokens[0].addCancellationHandler {
            harness.query.complete(.success(.playing))
        }

        harness.scheduler.advance(by: SpaceVisualizerLifecycleCoordinator.playbackQueryTimeoutNanoseconds)
        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertFalse(harness.coordinator.isQueryInFlight)
        XCTAssertEqual(harness.factory.creationCount, 0)
        XCTAssertEqual(harness.coordinator.message, "Music playback check timed out.")
    }

    func testCompletedQueryCancelsItsDeadline() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.query.complete(.success(.paused))
        XCTAssertEqual(harness.scheduler.activeHandleCount, 1)
        harness.scheduler.advance(by: SpaceVisualizerLifecycleCoordinator.playbackQueryTimeoutNanoseconds)
        XCTAssertEqual(harness.coordinator.playback?.state, .paused)
        XCTAssertFalse(harness.coordinator.message.contains("timed out"))
        XCTAssertEqual(harness.query.queryCount, 1)
    }

    func testClosingWindowCancelsQueryDeadlineAndIgnoresLateResult() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.coordinator.closeWindow()
        XCTAssertTrue(harness.query.tokens[0].isCancelled)
        XCTAssertEqual(harness.scheduler.activeHandleCount, 0)
        harness.scheduler.advance(by: 10_000_000_000)
        harness.query.complete(.success(.playing))
        XCTAssertEqual(harness.coordinator.state, .suspended)
        XCTAssertFalse(harness.coordinator.isQueryInFlight)
        XCTAssertEqual(harness.factory.creationCount, 0)
    }

    func testRepeatedAudioFramesUseLatestMailboxWithoutRepeatingStatusUpdates() {
        let harness = LifecycleHarness()
        var statusChanges = 0
        var latestAudio: AudioFeatures?
        harness.coordinator.stateDidChange = { _ in statusChanges += 1 }
        harness.coordinator.audioFeaturesDidChange = { latestAudio = $0 }
        harness.startFollowing()
        harness.query.complete(.success(.playing))
        harness.factory.completeSuccess()
        let statusBeforeAudio = statusChanges
        let generation = harness.coordinator.generation

        for timestamp in 1...20 {
            harness.coordinator.receiveAudio(
                AudioFeatures(
                    timestamp: UInt64(timestamp),
                    rms: 0.4,
                    peak: 0.8,
                    bass: 0.9,
                    mids: 0.3,
                    highs: 0.1,
                    isSilent: false,
                    isFresh: true,
                    generation: generation
                )
            )
        }

        XCTAssertEqual(statusChanges, statusBeforeAudio + 1)
        XCTAssertEqual(latestAudio?.timestamp, 20)
    }

    func testPlayingCancelsIdleTimerAndActiveWatchdogIsTheOnlyPeriodicObserver() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.query.complete(.success(.playing))

        XCTAssertFalse(harness.coordinator.hasIdleTimer)
        XCTAssertTrue(harness.coordinator.hasActiveWatchdog)
        // The initial query deadline is canceled; only the watchdog remains.
        XCTAssertEqual(harness.scheduler.activeHandleCount, 1)

        harness.query.complete(.success(.playing))
        XCTAssertEqual(harness.factory.creationCount, 1)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
    }

    func testActiveWatchdogAndNotificationHintsCoalesceQueries() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.query.complete(.success(.playing))
        harness.factory.completeSuccess()

        harness.scheduler.advance(by: 2_000_000_000)
        XCTAssertEqual(harness.query.queryCount, 2)
        harness.coordinator.playbackNotificationHint()
        harness.coordinator.playbackNotificationHint()
        XCTAssertEqual(harness.query.queryCount, 2)

        harness.query.complete(.success(.playing))
        XCTAssertEqual(harness.query.queryCount, 3)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 1)
    }

    func testActivePauseTearsDownBeforeReturningToIdleDiscovery() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.query.complete(.success(.playing))
        harness.factory.completeSuccess()
        harness.coordinator.receiveAudio(.fixtureLive.withGeneration(harness.coordinator.generation))

        harness.scheduler.advance(by: 2_000_000_000)
        harness.query.complete(.success(.paused))

        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
        XCTAssertTrue(harness.coordinator.hasIdleTimer)
        XCTAssertFalse(harness.coordinator.hasActiveWatchdog)
        XCTAssertEqual(harness.capture.stopCount, 1)
        XCTAssertEqual(harness.capture.destroyCount, 1)
    }

    func testTrackTransitionUpdatesPlaybackWithoutDuplicatingSession() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        let first = PlaybackObservation(state: .playing, track: .fixtureTrack)
        let secondTrack = TrackSnapshot(title: "Second", artist: "Artist", playbackState: .playing)
        harness.query.complete(.success(first))
        harness.factory.completeSuccess()

        harness.scheduler.advance(by: 2_000_000_000)
        harness.query.complete(.success(PlaybackObservation(state: .playing, track: secondTrack)))

        XCTAssertEqual(harness.coordinator.playback?.track, secondTrack)
        XCTAssertEqual(harness.factory.creationCount, 1)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 1)
    }

    func testMusicQuitIsNotConfusedWithFreshSilence() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.query.complete(.success(.playing))
        harness.factory.completeSuccess()
        harness.coordinator.receiveAudio(.fixtureSilent.withGeneration(harness.coordinator.generation))
        XCTAssertEqual(harness.coordinator.state, .silent)

        harness.scheduler.advance(by: 2_000_000_000)
        harness.query.complete(.success(PlaybackObservation(state: .stopped, isPlayerAvailable: false)))

        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
        XCTAssertTrue(harness.coordinator.hasIdleTimer)
    }

    func testUnavailableMusicKeepsOneIdleTimerAndCreatesNoResources() {
        let harness = LifecycleHarness()
        harness.startFollowing()
        harness.query.complete(.success(PlaybackObservation(state: .stopped, isPlayerAvailable: false)))

        for _ in 0..<20 {
            harness.scheduler.advance(by: SpaceVisualizerLifecycleCoordinator.idleIntervalNanoseconds)
            harness.query.complete(.success(PlaybackObservation(state: .stopped, isPlayerAvailable: false)))
            XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
            XCTAssertEqual(harness.factory.creationCount, 0)
            XCTAssertLessThanOrEqual(harness.scheduler.activeHandleCount, 1)
        }

        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertTrue(harness.coordinator.hasIdleTimer)
    }

    func testRepeatedTransitionsKeepTimerAndSessionHandlesBounded() {
        let harness = LifecycleHarness()
        harness.startFollowing()

        for cycle in 0..<20 {
            harness.query.complete(.success(.playing))
            harness.factory.completeSuccess()
            // An active capture owns only its 2 s watchdog and the bounded
            // 1 s / 5 s fresh-input deadlines; none accumulate across cycles.
            XCTAssertLessThanOrEqual(harness.scheduler.activeHandleCount, 3)
            harness.scheduler.advance(by: 2_000_000_000)
            harness.query.complete(.success(.paused))
            XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
            XCTAssertLessThanOrEqual(harness.scheduler.activeHandleCount, 1)
            if cycle < 19 { harness.scheduler.advance(by: 5_000_000_000) }
        }

        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertTrue(harness.coordinator.hasIdleTimer)
        XCTAssertFalse(harness.coordinator.hasActiveWatchdog)
    }
}

private final class LifecycleHarness {
    let scheduler = FakeMonotonicScheduler()
    let query = LifecyclePlaybackQueryFake()
    let permissions = LifecyclePermissionFake()
    let factory = LifecycleSessionFactoryFake()
    lazy var coordinator = SpaceVisualizerLifecycleCoordinator(
        scheduler: scheduler,
        playbackQuery: query,
        permissions: permissions,
        sessionFactory: factory
    )
    lazy var capture = factory.capture

    func startFollowing() {
        coordinator.openWindow()
        coordinator.enableAutomaticFollowing()
    }
}

private final class LifecyclePermissionFake: LifecyclePermissionProviding {
    var permissions = LifecyclePermissionSnapshot(automation: .authorized, systemAudio: .authorized)
    private(set) var automationRequests = 0
    private(set) var systemAudioRequests = 0

    func requestAutomationPermission() -> AudioPermissionStatus {
        automationRequests += 1
        return permissions.automation
    }

    func requestSystemAudioPermission() -> AudioPermissionStatus {
        systemAudioRequests += 1
        return permissions.systemAudio
    }
}

private final class LifecyclePlaybackQueryFake: PlaybackStateQuerying {
    private(set) var queryCount = 0
    private(set) var inFlightCount = 0
    private(set) var tokens: [LifecycleCancellationToken] = []
    private var completions: [(PlaybackQueryResult) -> Void] = []

    @discardableResult
    func query(completion: @escaping (PlaybackQueryResult) -> Void) -> LifecycleCancellationToken {
        queryCount += 1
        inFlightCount += 1
        completions.append(completion)
        let token = LifecycleCancellationToken()
        tokens.append(token)
        return token
    }

    func complete(_ result: PlaybackQueryResult) {
        guard !completions.isEmpty else { return }
        let completion = completions.removeFirst()
        inFlightCount = max(0, inFlightCount - 1)
        completion(result)
    }
}

private final class LifecycleSessionFactoryFake: VisualizerSessionFactory {
    private(set) var creationCount = 0
    private var completions: [(Result<VisualizerSessionResources, Error>) -> Void] = []
    let capture = LifecycleCaptureFake()
    private let worker = LifecycleWorkerFake()
    private let renderer = LifecycleRendererFake()
    var nextStartError: Error?

    @discardableResult
    func makeSession(
        for observation: PlaybackObservation,
        generation: UInt64,
        completion: @escaping (Result<VisualizerSessionResources, Error>) -> Void
    ) -> LifecycleCancellationToken {
        creationCount += 1
        completions.append(completion)
        return LifecycleCancellationToken()
    }

    func completeSuccess() {
        guard !completions.isEmpty else { return }
        let completion = completions.removeFirst()
        if let nextStartError {
            self.nextStartError = nil
            completion(.failure(nextStartError))
            return
        }
        completion(.success(VisualizerSessionResources(capture: capture, worker: worker, renderer: renderer)))
    }

    func completeFailure() {
        guard !completions.isEmpty else { return }
        let completion = completions.removeFirst()
        completion(.failure(FixtureError()))
    }
}

private final class LifecycleCaptureFake: CaptureResourceLifecycle {
    private(set) var starts = 0
    private(set) var stopCount = 0
    private(set) var destroyCount = 0
    var startError: Error?

    func start() throws {
        starts += 1
        if let startError { throw startError }
    }

    func stop() { stopCount += 1 }
    func destroy() { destroyCount += 1 }
}

private final class LifecycleWorkerFake: LifecycleWorkerResource {
    private(set) var starts = 0
    private(set) var stops = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
}

private final class LifecycleRendererFake: LifecycleRendererResource {
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var clears = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
    func clear() { clears += 1 }
}

private extension PlaybackObservation {
    static let paused = PlaybackObservation(state: .paused)
    static let playing = PlaybackObservation(state: .playing)
}

private extension AudioFeatures {
    func withGeneration(_ generation: UInt64) -> AudioFeatures {
        AudioFeatures(timestamp: timestamp, rms: rms, peak: peak, bass: bass, mids: mids,
                      highs: highs, bands: bands, isSilent: isSilent, isFresh: isFresh,
                      generation: generation)
    }
}
