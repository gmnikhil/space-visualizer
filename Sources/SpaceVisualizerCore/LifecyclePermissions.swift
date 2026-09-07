import Foundation

/// macOS does not expose a general, reliable Automation preflight that can be
/// treated as TCC truth. This provider starts as `.notDetermined`, permits an
/// explicit user-enabled query to prompt, and records only its real outcome.
public final class SystemLifecyclePermissionProvider: LifecyclePermissionProviding, LifecyclePermissionOutcomeRecording {
    private let systemAudioProvider: AudioPermissionProviding
    private var automationStatus: AudioPermissionStatus

    public init(
        systemAudioProvider: AudioPermissionProviding = SystemAudioPermissionProvider(),
        automationStatus: AudioPermissionStatus = .notDetermined
    ) {
        self.systemAudioProvider = systemAudioProvider
        self.automationStatus = automationStatus
    }

    public var permissions: LifecyclePermissionSnapshot {
        LifecyclePermissionSnapshot(automation: automationStatus, systemAudio: systemAudioProvider.status)
    }

    /// The query helper sends the first Automation event only after explicit
    /// consent. Its result is recorded through `recordPlaybackQueryResult`.
    public func requestAutomationPermission() -> AudioPermissionStatus {
        automationStatus
    }

    /// Process-tap creation is the platform operation that presents the
    /// system-audio prompt. This method never requests microphone access.
    public func requestSystemAudioPermission() -> AudioPermissionStatus {
        systemAudioProvider.requestPermission()
    }

    public func recordPlaybackQueryResult(_ result: PlaybackQueryResult) {
        switch result {
        case .success:
            automationStatus = .authorized
        case .denied:
            automationStatus = .denied
        case .timedOut, .canceled, .failed:
            break
        }
    }
}
