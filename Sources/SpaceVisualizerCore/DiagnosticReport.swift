import Foundation

public enum TestPhase: String, Codable, CaseIterable, Equatable, Sendable {
    case unprotectedControl = "unprotected-control"
    case streamedSubscription = "streamed-subscription"
    case downloadedSubscription = "downloaded-subscription"
}

public enum FeasibilityResult: String, Codable, Equatable, Sendable {
    case pass
    case fail
    case inconclusive
}

public struct TestEvidence: Codable, Equatable, Sendable {
    public var id: UUID
    public var phase: TestPhase
    public var startedAt: Date
    public var buildContext: String
    public var route: AudioRouteFacts?
    public var format: AudioFormatFacts?
    public var automationPermission: String
    public var systemAudioPermission: String
    public var metadataAvailable: Bool
    public var playbackAudible: Bool
    public var freshSamples: Bool
    public var controlVerified: Bool
    public var signalPresent: Bool
    public var expectedBand: String?
    public var measuredBand: String?
    public var rms: Float?
    public var events: [String]
    public var result: FeasibilityResult

    public init(
        id: UUID = UUID(),
        phase: TestPhase,
        startedAt: Date = Date(),
        buildContext: String,
        route: AudioRouteFacts? = nil,
        format: AudioFormatFacts? = nil,
        automationPermission: String,
        systemAudioPermission: String,
        metadataAvailable: Bool,
        playbackAudible: Bool,
        freshSamples: Bool,
        controlVerified: Bool,
        signalPresent: Bool,
        expectedBand: String? = nil,
        measuredBand: String? = nil,
        rms: Float? = nil,
        events: [String] = [],
        result: FeasibilityResult
    ) {
        self.id = id
        self.phase = phase
        self.startedAt = startedAt
        self.buildContext = buildContext
        self.route = route
        self.format = format
        self.automationPermission = automationPermission
        self.systemAudioPermission = systemAudioPermission
        self.metadataAvailable = metadataAvailable
        self.playbackAudible = playbackAudible
        self.freshSamples = freshSamples
        self.controlVerified = controlVerified
        self.signalPresent = signalPresent
        self.expectedBand = expectedBand
        self.measuredBand = measuredBand
        self.rms = rms
        self.events = events
        self.result = result
    }
}

public struct DiagnosticReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var createdAt: Date
    public var appBuild: String
    public var tests: [TestEvidence]

    public init(schemaVersion: Int = 1, createdAt: Date = Date(), appBuild: String, tests: [TestEvidence]) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.appBuild = appBuild
        self.tests = tests
    }

    public func encodedJSON(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrinted { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return try encoder.encode(self)
    }
}

/// Audio-free runtime export for the automatic product shell. It contains
/// lifecycle/permission status and bounded timing summaries, never PCM,
/// artwork, or a screen recording.
public struct SpaceVisualizerDiagnosticsExport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let createdAt: Date
    public let appBuild: String
    public let lifecycleState: String
    public let lifecycleMessage: String
    public let consentIntent: Bool
    public let isWindowVisible: Bool
    public let playbackState: String?
    public let legacyReport: DiagnosticReport?
    public let display: DisplayTelemetrySnapshot

    public init(
        appBuild: String,
        presentation: LifecyclePresentation,
        legacyReport: DiagnosticReport? = nil,
        display: DisplayTelemetrySnapshot = DisplayTelemetrySnapshot(),
        schemaVersion: Int = 1,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.appBuild = appBuild
        self.lifecycleState = presentation.state.rawValue
        self.lifecycleMessage = presentation.message
        self.consentIntent = presentation.consentIntent
        self.isWindowVisible = presentation.isWindowVisible
        self.playbackState = presentation.playback?.state.rawValue
        self.legacyReport = legacyReport
        self.display = display
    }

    public func encodedJSON(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrinted { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return try encoder.encode(self)
    }
}

public enum FeasibilityClassifier {
    public static func classify(_ evidence: TestEvidence) -> FeasibilityResult {
        guard evidence.systemAudioPermission == AudioPermissionStatus.authorized.rawValue else { return .inconclusive }
        guard evidence.route != nil, evidence.format != nil else { return .inconclusive }

        switch evidence.phase {
        case .unprotectedControl:
            guard hasCorrelatedSignal(evidence), evidence.controlVerified else { return .inconclusive }
            return .pass
        case .streamedSubscription, .downloadedSubscription:
            guard hasCorrelatedSignal(evidence), evidence.controlVerified else { return .inconclusive }
            return .pass
        }
    }

    private static func hasCorrelatedSignal(_ evidence: TestEvidence) -> Bool {
        guard evidence.playbackAudible,
              evidence.freshSamples,
              evidence.signalPresent,
              let expectedBand = normalizedBand(evidence.expectedBand),
              let measuredBand = normalizedBand(evidence.measuredBand) else {
            return false
        }
        return expectedBand == measuredBand
    }

    private static func normalizedBand(_ band: String?) -> String? {
        guard let band else { return nil }
        let normalized = band.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    public static func explanation(for result: FeasibilityResult) -> String {
        switch result {
        case .pass:
            return "Fresh audio samples correlated with audible playback on the tested route."
        case .fail:
            return "The tested playback did not produce a usable correlated signal. Review the recorded evidence."
        case .inconclusive:
            return "The result is inconclusive. Verify the control path, permissions, source, route, audibility, and silence before drawing a conclusion."
        }
    }
}
