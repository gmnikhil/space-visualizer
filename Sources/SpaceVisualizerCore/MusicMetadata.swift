import Foundation

public enum MusicBridgeError: Error, Equatable, LocalizedError, Sendable {
    case automationDenied
    case musicUnavailable
    case invalidResponse(String)
    case scriptFailed(String)
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .automationDenied:
            return "Music automation permission is required."
        case .musicUnavailable:
            return "Music is not available."
        case let .invalidResponse(message), let .scriptFailed(message):
            return message
        case .unsupportedPlatform:
            return "The Music bridge is available only on macOS."
        }
    }
}

public enum MetadataRefreshResult: Equatable, Sendable {
    case available(TrackSnapshot)
    case permissionRequired(String)
    case unavailable(String)
    case throttled
}

public enum MusicMetadataNormalizer {
    public static func normalize(_ raw: RawMusicSnapshot) -> TrackSnapshot {
        TrackSnapshot(
            title: clean(raw.title),
            artist: clean(raw.artist),
            album: clean(raw.album),
            playbackState: raw.playbackState,
            position: validTime(raw.position),
            duration: validDuration(raw.duration),
            artworkAvailable: raw.artworkAvailable
        )
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func validTime(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func validDuration(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}

public final class MusicMetadataCoordinator {
    private let query: MusicQuerying
    private let clock: SpaceVisualizerClock
    private let minimumRefreshIntervalNanoseconds: UInt64
    private var lastRefreshNanoseconds: UInt64?
    private var requiresUserRetry = false

    public private(set) var health: MetadataHealth = .unknown
    public private(set) var snapshot: TrackSnapshot?

    public init(
        query: MusicQuerying,
        clock: SpaceVisualizerClock = SystemSpaceVisualizerClock(),
        minimumRefreshIntervalNanoseconds: UInt64 = 500_000_000
    ) {
        self.query = query
        self.clock = clock
        self.minimumRefreshIntervalNanoseconds = minimumRefreshIntervalNanoseconds
    }

    @discardableResult
    public func refresh(force: Bool = false) -> MetadataRefreshResult {
        let now = clock.uptimeNanoseconds()
        if requiresUserRetry && !force { return .throttled }
        if !force, let lastRefreshNanoseconds,
           now >= lastRefreshNanoseconds,
           now - lastRefreshNanoseconds < minimumRefreshIntervalNanoseconds {
            return .throttled
        }
        lastRefreshNanoseconds = now

        do {
            let nextSnapshot = MusicMetadataNormalizer.normalize(try query.query())
            snapshot = nextSnapshot
            health = .available
            requiresUserRetry = false
            return .available(nextSnapshot)
        } catch let error as MusicBridgeError {
            switch error {
            case .automationDenied:
                health = .permissionRequired
                requiresUserRetry = true
                return .permissionRequired(error.localizedDescription)
            default:
                health = .unavailable
                return .unavailable(error.localizedDescription)
            }
        } catch {
            health = .unavailable
            return .unavailable(error.localizedDescription)
        }
    }
}

/// Legacy diagnostic views retain this inert query only so they cannot
/// accidentally restore the removed synchronous AppleScript observation path.
public final class UnavailableMusicMetadataQuery: MusicQuerying {
    public init() {}

    public func query() throws -> RawMusicSnapshot {
        throw MusicBridgeError.musicUnavailable
    }
}
