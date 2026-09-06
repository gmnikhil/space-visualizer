import Foundation
import Combine

public enum PlaybackState: String, Codable, Equatable, Sendable {
    case playing
    case paused
    case stopped
    case unknown
}

public enum MetadataHealth: String, Codable, Equatable, Sendable {
    case unknown
    case permissionRequired
    case available
    case unavailable
}

public enum AudioHealth: String, Codable, Equatable, Sendable {
    case unknown
    case permissionRequired
    case connecting
    case live
    case silent
    case unavailable
    case reconnecting
    case failed
    case stopped
}

public enum CaptureState: String, Codable, Equatable, Sendable {
    case idle
    case permissionRequired
    case connecting
    case active
    case reconnecting
    case failed
    case stopped
}

public enum AudioRouteKind: String, Codable, Equatable, Sendable {
    case builtInSpeaker
    case airPlay
    case headphones
    case other
    case unknown
}

public enum AudioSampleFormat: String, Codable, Equatable, Sendable {
    case float32
    case int16
    case int32
    case unknown
}

public enum ProcessTapMuteBehavior: String, Codable, Equatable, Sendable {
    case unmuted
}

public struct ProcessTapPolicy: Codable, Equatable, Sendable {
    public let targetBundleIdentifier: String
    public let routeID: String
    public let isPrivate: Bool
    public let isExclusive: Bool
    public let isMixdown: Bool
    public let isMono: Bool
    public let muteBehavior: ProcessTapMuteBehavior

    public init(
        targetBundleIdentifier: String,
        routeID: String,
        isPrivate: Bool,
        isExclusive: Bool,
        isMixdown: Bool,
        isMono: Bool,
        muteBehavior: ProcessTapMuteBehavior
    ) {
        self.targetBundleIdentifier = targetBundleIdentifier
        self.routeID = routeID
        self.isPrivate = isPrivate
        self.isExclusive = isExclusive
        self.isMixdown = isMixdown
        self.isMono = isMono
        self.muteBehavior = muteBehavior
    }

    public static func music(routeID: String) -> ProcessTapPolicy {
        ProcessTapPolicy(
            targetBundleIdentifier: "com.apple.Music",
            routeID: routeID,
            isPrivate: true,
            isExclusive: false,
            isMixdown: true,
            isMono: false,
            muteBehavior: .unmuted
        )
    }

    public var capturesOnlyTargetProcess: Bool { true }
    public var leavesPlaybackUnmuted: Bool { muteBehavior == .unmuted }
}

public struct TrackSnapshot: Codable, Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var playbackState: PlaybackState
    public var position: Double?
    public var duration: Double?
    public var artworkAvailable: Bool

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        playbackState: PlaybackState = .unknown,
        position: Double? = nil,
        duration: Double? = nil,
        artworkAvailable: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.playbackState = playbackState
        self.position = position
        self.duration = duration
        self.artworkAvailable = artworkAvailable
    }
}

public struct RawMusicSnapshot: Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var playbackState: PlaybackState
    public var position: Double?
    public var duration: Double?
    public var artworkAvailable: Bool

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        playbackState: PlaybackState = .unknown,
        position: Double? = nil,
        duration: Double? = nil,
        artworkAvailable: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.playbackState = playbackState
        self.position = position
        self.duration = duration
        self.artworkAvailable = artworkAvailable
    }

    public static let unknown = RawMusicSnapshot()
}

public protocol MusicQuerying {
    func query() throws -> RawMusicSnapshot
}

public struct AudioRouteFacts: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: AudioRouteKind
    public var isActive: Bool
    public var sampleRate: Double?
    public var channelCount: Int?

    public init(
        id: String,
        name: String,
        kind: AudioRouteKind,
        isActive: Bool,
        sampleRate: Double? = nil,
        channelCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isActive = isActive
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

public struct AudioFormatFacts: Codable, Equatable, Sendable {
    public var sampleRate: Double
    public var channelCount: Int
    public var isInterleaved: Bool
    public var sampleFormat: AudioSampleFormat

    public init(
        sampleRate: Double,
        channelCount: Int,
        isInterleaved: Bool,
        sampleFormat: AudioSampleFormat
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.isInterleaved = isInterleaved
        self.sampleFormat = sampleFormat
    }
}

public struct AudioFeatures: Codable, Equatable, Sendable {
    public var timestamp: UInt64
    public var rms: Float
    public var peak: Float
    public var bass: Float
    public var mids: Float
    public var highs: Float
    public var bands: [Float]
    public var isSilent: Bool
    public var isFresh: Bool
    public var generation: UInt64

    public init(
        timestamp: UInt64,
        rms: Float,
        peak: Float,
        bass: Float,
        mids: Float,
        highs: Float,
        bands: [Float] = [],
        isSilent: Bool,
        isFresh: Bool,
        generation: UInt64
    ) {
        self.timestamp = timestamp
        self.rms = rms
        self.peak = peak
        self.bass = bass
        self.mids = mids
        self.highs = highs
        self.bands = bands
        self.isSilent = isSilent
        self.isFresh = isFresh
        self.generation = generation
    }
}

public extension AudioFeatures {
    static let settled = AudioFeatures(
        timestamp: 0,
        rms: 0,
        peak: 0,
        bass: 0,
        mids: 0,
        highs: 0,
        isSilent: true,
        isFresh: false,
        generation: 0
    )
}

public enum DiagnosticDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case combined
    case twoD
    case threeD

    public var id: Self { self }

    public var title: String {
        switch self {
        case .combined: return "2D + 3D"
        case .twoD: return "2D signal"
        case .threeD: return "3D shape"
        }
    }
}

public struct VisualPreviewPolicy: Equatable, Sendable {
    public let ringCount: Int
    public let pointCount: Int
    public let isFeatureDriven: Bool
    public let reduceMotion: Bool

    public init(features: AudioFeatures, reduceMotion: Bool) {
        self.ringCount = reduceMotion ? 7 : 13
        self.pointCount = reduceMotion ? 48 : 96
        self.isFeatureDriven = features.isFresh && !features.isSilent
        self.reduceMotion = reduceMotion
    }
}

public struct VisualParameters: Codable, Equatable, Sendable {
    public var expansion: Float
    public var deformation: Float
    public var edgeDetail: Float

    public init(expansion: Float, deformation: Float, edgeDetail: Float) {
        self.expansion = expansion
        self.deformation = deformation
        self.edgeDetail = edgeDetail
    }

    public static let settled = VisualParameters(expansion: 0, deformation: 0, edgeDetail: 0)

    public init(features: AudioFeatures) {
        guard features.isFresh, !features.isSilent else {
            self = .settled
            return
        }
        self.init(
            expansion: Self.clamp(features.bass),
            deformation: Self.clamp(features.mids),
            edgeDetail: Self.clamp(features.highs)
        )
    }

    private static func clamp(_ value: Float) -> Float {
        min(1, max(0, value.isFinite ? value : 0))
    }
}

public struct DiagnosticState: Equatable, Sendable {
    public var captureState: CaptureState
    public var metadataHealth: MetadataHealth
    public var audioHealth: AudioHealth
    public var track: TrackSnapshot?
    public var route: AudioRouteFacts?
    public var format: AudioFormatFacts?
    public var latestFeatures: AudioFeatures?
    public var message: String
    public private(set) var playbackCommandsIssued: Int

    public init(
        captureState: CaptureState = .idle,
        metadataHealth: MetadataHealth = .unknown,
        audioHealth: AudioHealth = .unknown,
        track: TrackSnapshot? = nil,
        route: AudioRouteFacts? = nil,
        format: AudioFormatFacts? = nil,
        latestFeatures: AudioFeatures? = nil,
        message: String = "Ready when you are.",
        playbackCommandsIssued: Int = 0
    ) {
        self.captureState = captureState
        self.metadataHealth = metadataHealth
        self.audioHealth = audioHealth
        self.track = track
        self.route = route
        self.format = format
        self.latestFeatures = latestFeatures
        self.message = message
        self.playbackCommandsIssued = playbackCommandsIssued
    }

    public var isLiveSignal: Bool {
        audioHealth == .live && latestFeatures?.isFresh == true && latestFeatures?.isSilent == false
    }
}

public enum DiagnosticTransition: Equatable, Sendable {
    case reset
    case start
    case metadataPermissionRequired
    case metadataAvailable(TrackSnapshot)
    case metadataUnavailable(String)
    case capturePermissionRequired
    case capturePermissionDenied(String)
    case captureConnecting
    case captureStarted(route: AudioRouteFacts, format: AudioFormatFacts)
    case captureNoSamples
    case features(AudioFeatures)
    case routeChanged(String)
    case captureFailed(String)
    case stopped
}

public struct DiagnosticStateMachine: Sendable {
    public private(set) var state: DiagnosticState

    public init(state: DiagnosticState = DiagnosticState()) {
        self.state = state
    }

    public mutating func transition(_ event: DiagnosticTransition) {
        switch event {
        case .reset:
            state = DiagnosticState()

        case .start:
            state.captureState = .permissionRequired
            state.audioHealth = .permissionRequired
            state.latestFeatures = nil
            state.message = "System-audio permission is required."

        case .metadataPermissionRequired:
            state.metadataHealth = .permissionRequired
            state.message = "Music automation permission is required."

        case let .metadataAvailable(track):
            state.metadataHealth = .available
            state.track = track
            state.message = "Music metadata available."

        case let .metadataUnavailable(message):
            state.metadataHealth = .unavailable
            state.message = message

        case .capturePermissionRequired:
            state.captureState = .permissionRequired
            state.audioHealth = .permissionRequired
            state.latestFeatures = nil
            state.message = "System-audio permission is required."

        case let .capturePermissionDenied(message):
            state.captureState = .failed
            state.audioHealth = .failed
            state.latestFeatures = nil
            state.message = message

        case .captureConnecting:
            state.captureState = .connecting
            state.audioHealth = .connecting
            state.latestFeatures = nil
            state.message = "Connecting to the selected audio source."

        case let .captureStarted(route, format):
            state.captureState = .active
            state.audioHealth = .connecting
            state.route = route
            state.format = format
            state.latestFeatures = nil
            state.message = "Capture started; waiting for fresh samples."

        case .captureNoSamples:
            state.captureState = .active
            state.audioHealth = .unavailable
            state.latestFeatures = nil
            state.message = "Capture is active, but no complete fresh audio frame has arrived."

        case let .features(features):
            state.latestFeatures = features
            state.captureState = .active
            if !features.isFresh {
                state.audioHealth = .unavailable
                state.message = "Audio samples are stale."
            } else if features.isSilent {
                state.audioHealth = .silent
                state.message = "The selected source is quiet or paused."
            } else {
                state.audioHealth = .live
                state.message = "Live signal available."
            }

        case let .routeChanged(routeName):
            state.captureState = .reconnecting
            state.audioHealth = .reconnecting
            state.latestFeatures = nil
            state.message = routeName

        case let .captureFailed(message):
            state.captureState = .failed
            state.audioHealth = .failed
            state.latestFeatures = nil
            state.message = message

        case .stopped:
            state.captureState = .stopped
            state.audioHealth = .stopped
            state.latestFeatures = nil
            state.message = "Capture stopped. Music playback was not changed."
        }
    }
}

public final class DiagnosticViewModel: ObservableObject {
    @Published public private(set) var state: DiagnosticState
    private var machine: DiagnosticStateMachine
    public let isPreview: Bool

    public init(state: DiagnosticState = DiagnosticState(), isPreview: Bool = false) {
        self.machine = DiagnosticStateMachine(state: state)
        self.state = state
        self.isPreview = isPreview
    }

    public static var preview: DiagnosticViewModel {
        DiagnosticViewModel(isPreview: true)
    }

    public func apply(_ event: DiagnosticTransition) {
        machine.transition(event)
        state = machine.state
    }

    public var title: String {
        isPreview ? "Resonant feasibility preview" : "Resonant diagnostic"
    }

    public var audioLabel: String {
        switch state.audioHealth {
        case .unknown: return "Not connected"
        case .permissionRequired: return "Permission required"
        case .connecting: return "Connecting"
        case .live: return "Live signal"
        case .silent: return "Silent"
        case .unavailable: return "Signal unavailable"
        case .reconnecting: return "Reconnecting"
        case .failed: return "Capture failed"
        case .stopped: return "Stopped"
        }
    }

    public var metadataLabel: String {
        switch state.metadataHealth {
        case .unknown: return "Track details unknown"
        case .permissionRequired: return "Music permission required"
        case .available: return "Track details available"
        case .unavailable: return "Track details unavailable"
        }
    }

    public var metadataTitleLabel: String { state.track?.title ?? "Unknown title" }
    public var metadataArtistLabel: String { state.track?.artist ?? "Unknown artist" }
    public var metadataAlbumLabel: String { state.track?.album ?? "Unknown album" }
    public var metadataPlaybackStateLabel: String { state.track?.playbackState.rawValue ?? "Unknown state" }
    public var metadataPositionLabel: String {
        guard let position = state.track?.position else { return "Unknown position" }
        return "\(Int(position.rounded())) s"
    }
    public var metadataDurationLabel: String {
        guard let duration = state.track?.duration else { return "Unknown duration" }
        return "\(Int(duration.rounded())) s"
    }
    public var metadataPermissionExplanation: String {
        "Resonant reads Music metadata only to show track identity and playback state; it does not control playback or sign in."
    }
    public var metadataRecoveryLabel: String {
        state.metadataHealth == .permissionRequired
            ? "Allow Music automation in System Settings, then retry."
            : "Retry Music metadata when Music is available."
    }
    public var showsMetadataRecovery: Bool { state.metadataHealth == .permissionRequired }

    public var isLive: Bool { state.isLiveSignal }

    public var canStartCapture: Bool {
        switch state.captureState {
        case .idle, .failed, .stopped: return true
        case .permissionRequired, .connecting, .active, .reconnecting: return false
        }
    }

    public var canStopCapture: Bool {
        switch state.captureState {
        case .permissionRequired, .connecting, .active, .reconnecting: return true
        case .idle, .failed, .stopped: return false
        }
    }

    public var liveLabel: String {
        isLive ? "LIVE · FRESH AUDIO" : "NOT LIVE · NO AUDIO-DRIVEN MOTION"
    }

    public var previewLabel: String { "FEASIBILITY PREVIEW · NOT PRODUCTION RENDERER" }

    public var signalFreshnessLabel: String {
        state.latestFeatures?.isFresh == true ? "Fresh samples" : "No fresh samples"
    }

    public var routeLabel: String {
        guard let route = state.route else { return "Route unknown" }
        return route.name
    }

    public var formatLabel: String {
        guard let format = state.format else { return "Format unknown" }
        return "\(Int(format.sampleRate)) Hz · \(format.channelCount) ch · \(format.sampleFormat.rawValue)"
    }

    public var bandLabels: [String] {
        guard let features = state.latestFeatures else { return ["Bass 0%", "Mids 0%", "Highs 0%"] }
        func percent(_ value: Float) -> String { "\(Int((value * 100).rounded()))%" }
        return ["Bass \(percent(features.bass))", "Mids \(percent(features.mids))", "Highs \(percent(features.highs))"]
    }

    public var visualParameters: VisualParameters {
        guard let latestFeatures = state.latestFeatures else { return .settled }
        return VisualParameters(features: latestFeatures)
    }
}

public protocol CaptureResourceLifecycle: AnyObject {
    func start() throws
    func stop()
    func destroy()
}

public protocol ResonantClock {
    func uptimeNanoseconds() -> UInt64
}

public struct SystemResonantClock: ResonantClock {
    public init() {}
    public func uptimeNanoseconds() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
}
