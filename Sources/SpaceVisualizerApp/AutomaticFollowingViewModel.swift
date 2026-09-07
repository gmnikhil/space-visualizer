import Combine
import Foundation
import SpaceVisualizerCore

/// Main-thread presentation adapter for the serialized lifecycle coordinator.
/// It persists user intent only; permission state always comes from current
/// platform work and never from the stored preference.
final class AutomaticFollowingViewModel: ObservableObject {
    @Published private(set) var presentation: LifecyclePresentation
    let visualFeatures = LatestAudioFeatures()

    private let coordinator: SpaceVisualizerLifecycleCoordinator

    init(coordinator: SpaceVisualizerLifecycleCoordinator) {
        self.coordinator = coordinator
        self.presentation = coordinator.presentation
        coordinator.audioFeaturesDidChange = { [weak self] features in
            self?.visualFeatures.update(features)
        }
        coordinator.stateDidChange = { [weak self] presentation in
            DispatchQueue.main.async {
                self?.presentation = presentation
            }
        }
    }

    static func live() -> AutomaticFollowingViewModel {
        let permissions = SystemLifecyclePermissionProvider()
        let coordinator = SpaceVisualizerLifecycleCoordinator(
            scheduler: DispatchMonotonicScheduler(),
            playbackQuery: MusicPlaybackQueryAdapter(),
            permissions: permissions,
            sessionFactory: DirectTapVisualizerSessionFactory(routeProvider: CoreAudioRouteProvider()),
            consentStore: UserDefaultsAutomaticFollowingConsentStore()
        )
        return AutomaticFollowingViewModel(coordinator: coordinator)
    }

    func openWindow() { coordinator.openWindow() }
    func setWindowVisible(_ visible: Bool) { coordinator.setWindowVisible(visible) }
    func closeWindow() { coordinator.closeWindow() }
    func sleep() { coordinator.sleep() }
    func wake() { coordinator.wake() }
    func quit() { coordinator.quit() }
    func enableAutomaticFollowing() { coordinator.enableAutomaticFollowing() }
    func latestFeatures() -> AudioFeatures { visualFeatures.snapshot() }

    func retry() {
        switch presentation.state {
        case .permissionBlocked:
            coordinator.retryPermission()
        case .failed:
            coordinator.retryAfterFailure()
        default:
            coordinator.enableAutomaticFollowing()
        }
    }
}
