import XCTest
@testable import SpaceVisualizerCore

final class PermissionOnboardingTests: XCTestCase {
    func testNoPermissionRequestOccursBeforeExplicitConsent() {
        let harness = PermissionHarness()

        harness.coordinator.openWindow()

        XCTAssertEqual(harness.permissions.automationRequests, 0)
        XCTAssertEqual(harness.permissions.systemAudioRequests, 0)
        XCTAssertEqual(harness.query.queryCount, 0)
        XCTAssertFalse(harness.store.automaticFollowingEnabled)
        XCTAssertEqual(harness.coordinator.state, .onboarding)
    }

    func testDeniedPermissionDoesNotPromptAgainOnIdleTicks() {
        let harness = PermissionHarness()
        harness.permissions.snapshot = .init(automation: .denied, systemAudio: .authorized)
        harness.coordinator.openWindow()
        harness.coordinator.enableAutomaticFollowing()

        XCTAssertEqual(harness.coordinator.state, .permissionBlocked)
        XCTAssertEqual(harness.permissions.automationRequests, 1)
        XCTAssertEqual(harness.permissions.systemAudioRequests, 1)
        XCTAssertTrue(harness.store.automaticFollowingEnabled)

        harness.scheduler.advance(by: 60_000_000_000)
        XCTAssertEqual(harness.permissions.automationRequests, 1)
        XCTAssertEqual(harness.permissions.systemAudioRequests, 1)
        XCTAssertEqual(harness.query.queryCount, 0)
    }

    func testKnownPermissionRevocationStopsActiveWorkSafely() {
        let harness = PermissionHarness()
        harness.coordinator.openWindow()
        harness.coordinator.enableAutomaticFollowing()
        harness.query.complete(.success(PlaybackObservation(state: .playing)))
        harness.factory.completeSuccess()

        harness.permissions.snapshot = .init(automation: .denied, systemAudio: .authorized)
        harness.scheduler.advance(by: SpaceVisualizerLifecycleCoordinator.activeWatchdogIntervalNanoseconds)

        XCTAssertEqual(harness.coordinator.state, .permissionBlocked)
        XCTAssertEqual(harness.coordinator.activeSessionCount, 0)
        XCTAssertEqual(harness.factory.capture.destroyCount, 1)
        XCTAssertFalse(harness.coordinator.hasIdleTimer)
        XCTAssertFalse(harness.coordinator.hasActiveWatchdog)
    }

    func testPersistedIntentAutomaticallyBeginsDiscoveryWhenPermissionsAreUsable() {
        let harness = PermissionHarness(persistedIntent: true)

        harness.coordinator.openWindow()

        XCTAssertTrue(harness.coordinator.consentIntent)
        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertEqual(harness.query.queryCount, 1)
        XCTAssertEqual(harness.permissions.automationRequests, 0)
        XCTAssertEqual(harness.permissions.systemAudioRequests, 0)
    }

    func testPersistedIntentIsNotTreatedAsCurrentTCCAuthorization() {
        let harness = PermissionHarness(persistedIntent: true)
        harness.permissions.snapshot = .init(automation: .denied, systemAudio: .authorized)

        harness.coordinator.openWindow()

        XCTAssertEqual(harness.coordinator.state, .permissionBlocked)
        XCTAssertEqual(harness.query.queryCount, 0)
        XCTAssertTrue(harness.store.automaticFollowingEnabled)
    }

    func testNotDeterminedPermissionsCanProceedOnlyAfterExplicitConsent() {
        let harness = PermissionHarness()
        harness.permissions.snapshot = .init(automation: .notDetermined, systemAudio: .notDetermined)
        harness.coordinator.openWindow()

        XCTAssertEqual(harness.coordinator.state, .onboarding)
        harness.coordinator.enableAutomaticFollowing()

        XCTAssertEqual(harness.coordinator.state, .waiting)
        XCTAssertEqual(harness.query.queryCount, 1)
        XCTAssertEqual(harness.permissions.automationRequests, 1)
        XCTAssertEqual(harness.permissions.systemAudioRequests, 1)
    }
}

private final class PermissionHarness {
    let scheduler = FakeMonotonicScheduler()
    let permissions = OnboardingPermissionFake()
    let query = OnboardingPlaybackQueryFake()
    let factory = OnboardingSessionFactoryFake()
    let store: InMemoryAutomaticFollowingConsentStore
    lazy var coordinator = SpaceVisualizerLifecycleCoordinator(
        scheduler: scheduler,
        playbackQuery: query,
        permissions: permissions,
        sessionFactory: factory,
        consentStore: store
    )

    init(persistedIntent: Bool = false) {
        store = InMemoryAutomaticFollowingConsentStore(automaticFollowingEnabled: persistedIntent)
    }
}

private final class OnboardingPermissionFake: LifecyclePermissionProviding {
    var snapshot = LifecyclePermissionSnapshot(automation: .authorized, systemAudio: .authorized)
    private(set) var automationRequests = 0
    private(set) var systemAudioRequests = 0

    var permissions: LifecyclePermissionSnapshot { snapshot }

    func requestAutomationPermission() -> AudioPermissionStatus {
        automationRequests += 1
        return snapshot.automation
    }

    func requestSystemAudioPermission() -> AudioPermissionStatus {
        systemAudioRequests += 1
        return snapshot.systemAudio
    }
}

private final class OnboardingPlaybackQueryFake: PlaybackStateQuerying {
    private(set) var queryCount = 0
    private var completion: ((PlaybackQueryResult) -> Void)?

    @discardableResult
    func query(completion: @escaping (PlaybackQueryResult) -> Void) -> LifecycleCancellationToken {
        queryCount += 1
        self.completion = completion
        return LifecycleCancellationToken()
    }

    func complete(_ result: PlaybackQueryResult) {
        let callback = completion
        completion = nil
        callback?(result)
    }
}

private final class OnboardingSessionFactoryFake: VisualizerSessionFactory {
    let capture = OnboardingCaptureFake()
    private let worker = OnboardingWorkerFake()
    private let renderer = OnboardingRendererFake()
    private var completion: ((Result<VisualizerSessionResources, Error>) -> Void)?

    @discardableResult
    func makeSession(
        for observation: PlaybackObservation,
        generation: UInt64,
        completion: @escaping (Result<VisualizerSessionResources, Error>) -> Void
    ) -> LifecycleCancellationToken {
        self.completion = completion
        return LifecycleCancellationToken()
    }

    func completeSuccess() {
        let callback = completion
        completion = nil
        callback?(.success(VisualizerSessionResources(capture: capture, worker: worker, renderer: renderer)))
    }
}

private final class OnboardingCaptureFake: CaptureResourceLifecycle {
    private(set) var destroyCount = 0
    func start() throws {}
    func stop() {}
    func destroy() { destroyCount += 1 }
}

private final class OnboardingWorkerFake: LifecycleWorkerResource {
    func start() {}
    func stop() {}
}

private final class OnboardingRendererFake: LifecycleRendererResource {
    func start() {}
    func stop() {}
    func clear() {}
}
