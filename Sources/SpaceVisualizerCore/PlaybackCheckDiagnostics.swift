import Foundation

/// Bounded, audio-free evidence of observation health. Timestamps describe
/// actual queries; a waiting-state message alone is not proof of polling.
public struct PlaybackCheckDiagnostics: Codable, Equatable, Sendable {
    public var lastStartedAt: Date?
    public var lastCompletedAt: Date?
    public var lastResult: String
    public var isChecking: Bool
    public var pollingStatus: String

    public init(lastStartedAt: Date? = nil, lastCompletedAt: Date? = nil,
                lastResult: String = "No check yet", isChecking: Bool = false,
                pollingStatus: String = "Stopped") {
        self.lastStartedAt = lastStartedAt
        self.lastCompletedAt = lastCompletedAt
        self.lastResult = lastResult
        self.isChecking = isChecking
        self.pollingStatus = pollingStatus
    }
}
