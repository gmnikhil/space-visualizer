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
    private let clock: ResonantClock
    private let minimumRefreshIntervalNanoseconds: UInt64
    private var lastRefreshNanoseconds: UInt64?
    private var requiresUserRetry = false

    public private(set) var health: MetadataHealth = .unknown
    public private(set) var snapshot: TrackSnapshot?

    public init(
        query: MusicQuerying,
        clock: ResonantClock = SystemResonantClock(),
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

#if os(macOS)
import AppKit

/// Reads the currently selected track from Music through its public AppleScript
/// dictionary. This adapter observes Music; it never starts playback or signs in.
public final class AppleScriptMusicQuery: MusicQuerying {
    public init() {}

    public func query() throws -> RawMusicSnapshot {
        let source = """
        tell application \"Music\"
            set currentTrack to current track
            set trackName to name of currentTrack
            set trackArtist to artist of currentTrack
            set trackAlbum to album of currentTrack
            set trackState to (player state as string)
            set trackPosition to player position
            set trackDuration to duration of currentTrack
            set hasArtwork to ((count of artworks of currentTrack) > 0)
            return {trackName, trackArtist, trackAlbum, trackState, trackPosition, trackDuration, hasArtwork}
        end tell
        """

        var scriptError: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&scriptError) else {
            if let number = scriptError?[NSAppleScript.errorNumber] as? NSNumber,
               number.intValue == -1743 || number.intValue == -1744 {
                throw MusicBridgeError.automationDenied
            }
            let message = (scriptError?[NSAppleScript.errorMessage] as? String) ?? "Music did not return a track."
            throw MusicBridgeError.scriptFailed(message)
        }

        guard result.numberOfItems >= 7 else {
            throw MusicBridgeError.invalidResponse("Music returned an incomplete track response.")
        }

        let state = Self.playbackState(from: result.atIndex(4)?.stringValue)
        let artwork = Self.boolean(from: result.atIndex(7))
        return RawMusicSnapshot(
            title: result.atIndex(1)?.stringValue,
            artist: result.atIndex(2)?.stringValue,
            album: result.atIndex(3)?.stringValue,
            playbackState: state,
            position: result.atIndex(5)?.doubleValue,
            duration: result.atIndex(6)?.doubleValue,
            artworkAvailable: artwork
        )
    }

    private static func playbackState(from value: String?) -> PlaybackState {
        switch value?.lowercased() {
        case "playing", "kpsp": return .playing
        case "paused", "kpss": return .paused
        case "stopped", "kpsm": return .stopped
        default: return .unknown
        }
    }

    private static func boolean(from descriptor: NSAppleEventDescriptor?) -> Bool {
        guard let descriptor else { return false }
        if descriptor.booleanValue { return true }
        return descriptor.stringValue?.lowercased() == "true"
    }
}
#else

public final class AppleScriptMusicQuery: MusicQuerying {
    public init() {}
    public func query() throws -> RawMusicSnapshot {
        throw MusicBridgeError.unsupportedPlatform
    }
}
#endif
