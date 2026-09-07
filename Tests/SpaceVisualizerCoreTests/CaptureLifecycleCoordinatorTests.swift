import XCTest
@testable import SpaceVisualizerCore

final class CaptureLifecycleCoordinatorTests: XCTestCase {
    func testCloseDuringPendingStartupDestroysLateResourcesWithoutPlaybackMutation() {
        let harness = CaptureLifecycleHarness()
        harness.beginPlayingSession()
        let generation = harness.coordinator.generation

        harness.coordinator.closeWindow()
        harness.factory.completeSuccess()

        XCTAssertEqual(harness.coordinator.state, .suspended)
        XCTAssertNotEqual(harness.coordinator.generation, generation)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
        XCTAssertEqual(harness.factory.capture.destroyCount, 1)
        XCTAssertEqual(harness.coordinator.playbackCommandsIssued, 0)
    }

    func testRepeatedCloseAndQuitAreIdempotentDuringAnActiveSession() {
        let harness = CaptureLifecycleHarness()
        harness.beginStartedSession()

        harness.coordinator.closeWindow()
        harness.coordinator.closeWindow()
        harness.coordinator.quit()
        harness.coordinator.quit()

        XCTAssertEqual(harness.coordinator.state, .terminated)
        XCTAssertEqual(harness.factory.capture.stopCount, 1)
        XCTAssertEqual(harness.factory.capture.destroyCount, 1)
        XCTAssertEqual(harness.coordinator.playbackCommandsIssued, 0)
    }

    func testSleepAndWakeDiscardOldSessionAndRequireFreshPlaybackValidation() {
        let harness = CaptureLifecycleHarness()
        harness.beginStartedSession()
        let queriesBeforeSleep = harness.query.queryCount

        harness.coordinator.sleep()
        XCTAssertEqual(harness.coordinator.state, .suspended)
        XCTAssertEqual(harness.factory.capture.destroyCount, 1)

        harness.coordinator.wake()
        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertEqual(harness.query.queryCount, queriesBeforeSleep + 1)
        harness.query.complete(.success(.playing))
        XCTAssertEqual(harness.factory.creationCount, 2)
    }

    func testPartialResourceStartFailureCleansUpWithoutMutatingPlayback() {
        let harness = CaptureLifecycleHarness()
        harness.beginPlayingSession()
        harness.factory.capture.startError = FixtureError()

        harness.factory.completeSuccess()

        XCTAssertEqual(harness.coordinator.state, .failed)
        XCTAssertEqual(harness.factory.capture.stopCount, 1)
        XCTAssertEqual(harness.factory.capture.destroyCount, 1)
        XCTAssertEqual(harness.coordinator.playbackCommandsIssued, 0)
    }

    func testRouteChangeInvalidatesGenerationTearsDownThenRevalidatesOnce() {
        let harness = CaptureLifecycleHarness()
        harness.beginStartedSession()
        let oldGeneration = harness.coordinator.generation

        harness.factory.worker.emit(.routeChanged("Built-in Speakers changed"))
        harness.coordinator.drainPendingLifecycleWork()

        XCTAssertGreaterThan(harness.coordinator.generation, oldGeneration)
        XCTAssertEqual(harness.factory.capture.destroyCount, 1)
        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertEqual(harness.query.queryCount, 2)

        harness.query.complete(.success(.playing))
        XCTAssertEqual(harness.factory.creationCount, 2)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
        harness.factory.completeSuccess()
        XCTAssertEqual(harness.coordinator.activeSessionCount, 1)
    }

    func testFormatChangeDiscardsOldSamplesBeforeRevalidatedSession() {
        let harness = CaptureLifecycleHarness()
        harness.beginStartedSession()
        let stale = AudioFeatures.fixtureLive.withGeneration(harness.coordinator.generation)

        harness.factory.worker.emit(.formatChanged(.fixtureStereo96k))
        harness.coordinator.drainPendingLifecycleWork()
        harness.coordinator.receiveAudio(stale)

        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertEqual(harness.factory.capture.destroyCount, 1)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
    }

    func testOneSecondNoInputStatusAndFiveSecondNoInputFailureRequireExplicitRetry() {
        let harness = CaptureLifecycleHarness()
        harness.beginStartedSession()

        harness.scheduler.advance(by: 1_000_000_000)
        XCTAssertEqual(harness.coordinator.state, .recovering)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 1)
        XCTAssertTrue(harness.coordinator.hasActiveWatchdog)

        harness.scheduler.advance(by: 4_000_000_000)
        XCTAssertEqual(harness.coordinator.state, .failed)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
        XCTAssertEqual(harness.factory.capture.destroyCount, 1)
        XCTAssertFalse(harness.coordinator.hasIdleTimer)
        XCTAssertFalse(harness.coordinator.hasActiveWatchdog)
    }

    func testExpiredInputClearsLatestVisualsWithoutTreatingMusicAsPaused() {
        let harness = CaptureLifecycleHarness()
        harness.beginStartedSession()
        let generation = harness.coordinator.generation
        harness.coordinator.receiveAudio(.fixtureLive.withGeneration(generation))
        var latest: AudioFeatures?
        harness.coordinator.audioFeaturesDidChange = { latest = $0 }

        harness.factory.worker.emit(.audio(AudioFeatures(
            timestamp: 99,
            rms: 0,
            peak: 0,
            bass: 0,
            mids: 0,
            highs: 0,
            isSilent: true,
            isFresh: false,
            generation: generation
        )))
        harness.coordinator.drainPendingLifecycleWork()

        XCTAssertEqual(harness.coordinator.state, .recovering)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 1)
        XCTAssertEqual(latest, .settled)
        XCTAssertTrue(harness.coordinator.hasActiveWatchdog)
    }

    func testFreshInputCancelsNoInputDeadlinesAndMakesSessionLive() {
        let harness = CaptureLifecycleHarness()
        harness.beginStartedSession()
        let generation = harness.coordinator.generation

        harness.factory.worker.emit(.audio(.fixtureLive.withGeneration(generation)))
        harness.coordinator.drainPendingLifecycleWork()
        XCTAssertEqual(harness.coordinator.state, .visualizing)

        harness.scheduler.advance(by: 5_000_000_000)
        XCTAssertNotEqual(harness.coordinator.state, .failed)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 1)
    }

    func testDelayedObsoleteFactoryCompletionIsDestroyedAfterSleepInvalidation() {
        let harness = CaptureLifecycleHarness()
        harness.beginPlayingSession()

        harness.coordinator.sleep()
        harness.factory.completeSuccess()

        XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
        XCTAssertEqual(harness.factory.capture.destroyCount, 1)
        XCTAssertEqual(harness.coordinator.state, .suspended)
    }
}

private final class CaptureLifecycleHarness {
    let scheduler = FakeMonotonicScheduler()
    let query = CapturePlaybackQueryFake()
    let permissions = CapturePermissionFake()
    let factory = CaptureSessionFactoryFake()
    lazy var coordinator = SpaceVisualizerLifecycleCoordinator(
        scheduler: scheduler,
        playbackQuery: query,
        permissions: permissions,
        sessionFactory: factory
    )

    func beginPlayingSession() {
        coordinator.openWindow()
        coordinator.enableAutomaticFollowing()
        query.complete(.success(.playing))
    }

    func beginStartedSession() {
        beginPlayingSession()
        factory.completeSuccess()
    }
}

private final class CapturePlaybackQueryFake: PlaybackStateQuerying {
    private(set) var queryCount = 0
    private var completions: [(PlaybackQueryResult) -> Void] = []

    @discardableResult
    func query(completion: @escaping (PlaybackQueryResult) -> Void) -> LifecycleCancellationToken {
        queryCount += 1
        completions.append(completion)
        return LifecycleCancellationToken()
    }

    func complete(_ result: PlaybackQueryResult) {
        guard !completions.isEmpty else { return }
        completions.removeFirst()(result)
    }
}

private final class CapturePermissionFake: LifecyclePermissionProviding {
    var permissions = LifecyclePermissionSnapshot(automation: .authorized, systemAudio: .authorized)
    func requestAutomationPermission() -> AudioPermissionStatus { permissions.automation }
    func requestSystemAudioPermission() -> AudioPermissionStatus { permissions.systemAudio }
}

private final class CaptureSessionFactoryFake: VisualizerSessionFactory {
    private(set) var creationCount = 0
    let capture = CaptureResourceFake()
    let worker = CaptureWorkerFake()
    let renderer = CaptureRendererFake()
    private var completions: [(Result<VisualizerSessionResources, Error>) -> Void] = []

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
        completion(.success(VisualizerSessionResources(capture: capture, worker: worker, renderer: renderer)))
    }
}

private final class CaptureResourceFake: CaptureResourceLifecycle {
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

private final class CaptureWorkerFake: LifecycleWorkerResource, LifecycleSessionEventStreaming {
    private var sink: ((LifecycleSessionEvent) -> Void)?
    private(set) var starts = 0
    private(set) var stops = 0

    func start() { starts += 1 }
    func stop() { stops += 1 }
    func setSessionEventSink(_ sink: @escaping (LifecycleSessionEvent) -> Void) { self.sink = sink }
    func emit(_ event: LifecycleSessionEvent) { sink?(event) }
}

private final class CaptureRendererFake: LifecycleRendererResource {
    func start() {}
    func stop() {}
    func clear() {}
}

private extension PlaybackObservation {
    static let playing = PlaybackObservation(state: .playing)
}

private extension AudioFormatFacts {
    static let fixtureStereo96k = AudioFormatFacts(
        sampleRate: 96_000,
        channelCount: 2,
        isInterleaved: true,
        sampleFormat: .float32
    )
}

private extension AudioFeatures {
    func withGeneration(_ generation: UInt64) -> AudioFeatures {
        AudioFeatures(timestamp: timestamp, rms: rms, peak: peak, bass: bass, mids: mids,
                      highs: highs, bands: bands, isSilent: isSilent, isFresh: isFresh,
                      generation: generation)
    }
}
