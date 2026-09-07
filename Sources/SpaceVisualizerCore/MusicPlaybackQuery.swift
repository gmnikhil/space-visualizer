import Foundation

/// Checks the running-application list before any Apple Event is sent. This is
/// the guard that keeps normal idle discovery from launching Music.
public protocol MusicProcessPresenceChecking: AnyObject {
    func isMusicRunning() -> Bool
}

#if os(macOS)
import AppKit

public final class MusicApplicationPresenceChecker: MusicProcessPresenceChecking {
    public init() {}

    public func isMusicRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }
}
#else
public final class MusicApplicationPresenceChecker: MusicProcessPresenceChecking {
    public init() {}
    public func isMusicRunning() -> Bool { false }
}
#endif

public enum AppleScriptRunnerError: Error, Equatable, LocalizedError, Sendable {
    case automationDenied(String)
    case timedOut
    case canceled
    case outputExceededLimit
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case let .automationDenied(message): return message
        case .timedOut: return "Music playback check timed out."
        case .canceled: return "Music playback check was canceled."
        case .outputExceededLimit: return "Music playback check returned too much output."
        case let .failed(message): return message
        }
    }
}

/// Runs a fixed local AppleScript without a shell. Implementations must bound
/// both execution time and retained stdout/stderr.
public protocol BoundedAppleScriptRunning: AnyObject {
    @discardableResult
    func run(
        fixedScript: String,
        timeout: TimeInterval,
        completion: @escaping (Result<String, AppleScriptRunnerError>) -> Void
    ) -> LifecycleCancellationToken
}

/// Converts the local helper's fixed, unit-separator-delimited response into a
/// playback result. This class deliberately has no API that accepts track text
/// or command fragments, so no user data can be interpolated into AppleScript.
public final class MusicPlaybackQueryAdapter: PlaybackStateQuerying {
    public static let timeout: TimeInterval = 1
    private static let fieldSeparator = "\u{1F}"

    /// Player state is read before, and independently from, optional current
    /// track properties. A missing current track therefore does not make state
    /// discovery fail. This script performs no playback mutation.
    public static let fixedScript = #"""
    set fieldSeparator to character id 31
    tell application id "com.apple.Music"
        set playerStateText to (player state as text)
        set trackTitle to ""
        set trackArtist to ""
        set trackAlbum to ""
        set trackPosition to ""
        set trackDuration to ""
        set trackHasArtwork to "false"
        try
            set currentMusicTrack to current track
            try
                set trackTitle to (name of currentMusicTrack as text)
            end try
            try
                set trackArtist to (artist of currentMusicTrack as text)
            end try
            try
                set trackAlbum to (album of currentMusicTrack as text)
            end try
            try
                set trackPosition to (player position as text)
            end try
            try
                set trackDuration to (duration of currentMusicTrack as text)
            end try
            try
                set trackHasArtwork to (((count of artworks of currentMusicTrack) > 0) as text)
            end try
        end try
        return playerStateText & fieldSeparator & trackTitle & fieldSeparator & trackArtist & fieldSeparator & trackAlbum & fieldSeparator & trackPosition & fieldSeparator & trackDuration & fieldSeparator & trackHasArtwork
    end tell
    """#

    private let presence: MusicProcessPresenceChecking
    private let runner: BoundedAppleScriptRunning
    private let queue: DispatchQueue

    public init(
        presence: MusicProcessPresenceChecking,
        runner: BoundedAppleScriptRunning,
        queue: DispatchQueue = DispatchQueue(label: "com.spacevisualizer.music-query", qos: .utility)
    ) {
        self.presence = presence
        self.runner = runner
        self.queue = queue
    }

    public convenience init() {
        self.init(presence: MusicApplicationPresenceChecker(), runner: BoundedAppleScriptRunner())
    }

    @discardableResult
    public func query(completion: @escaping (PlaybackQueryResult) -> Void) -> LifecycleCancellationToken {
        let token = LifecycleCancellationToken()
        let gate = CompletionGate(token: token, completion: completion)

        queue.async { [weak self, weak token] in
            guard let self, let token, !token.isCancelled else { return }
            guard self.presence.isMusicRunning() else {
                gate.complete(.success(PlaybackObservation(state: .stopped, isPlayerAvailable: false)))
                return
            }

            let runnerToken = self.runner.run(fixedScript: Self.fixedScript, timeout: Self.timeout) { result in
                self.queue.async {
                    guard !token.isCancelled else { return }
                    gate.complete(Self.map(result))
                }
            }
            token.addCancellationHandler { runnerToken.cancel() }
        }
        return token
    }

    private static func map(_ result: Result<String, AppleScriptRunnerError>) -> PlaybackQueryResult {
        switch result {
        case let .success(output):
            guard let observation = parse(output) else {
                return .failed("Music returned a malformed playback response.")
            }
            return .success(observation)
        case let .failure(error):
            switch error {
            case let .automationDenied(message): return .denied(message)
            case .timedOut: return .timedOut
            case .canceled: return .canceled
            case .outputExceededLimit, .failed:
                return .failed(error.localizedDescription)
            }
        }
    }

    private static func parse(_ output: String) -> PlaybackObservation? {
        let response = output.trimmingCharacters(in: .newlines)
        let values = response.components(separatedBy: fieldSeparator)
        guard values.count == 7 else { return nil }

        let raw = RawMusicSnapshot(
            title: emptyToNil(values[1]),
            artist: emptyToNil(values[2]),
            album: emptyToNil(values[3]),
            playbackState: playbackState(values[0]),
            position: Double(values[4].trimmingCharacters(in: .whitespacesAndNewlines)),
            duration: Double(values[5].trimmingCharacters(in: .whitespacesAndNewlines)),
            artworkAvailable: bool(values[6])
        )
        return PlaybackObservation(state: raw.playbackState, track: MusicMetadataNormalizer.normalize(raw))
    }

    private static func emptyToNil(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func playbackState(_ value: String) -> PlaybackState {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "playing", "kpsp": return .playing
        case "paused", "kpss": return .paused
        case "stopped", "kpsm": return .stopped
        default: return .unknown
        }
    }

    private static func bool(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes": return true
        default: return false
        }
    }

    private final class CompletionGate {
        private let lock = NSLock()
        private let token: LifecycleCancellationToken
        private let completion: (PlaybackQueryResult) -> Void
        private var didComplete = false

        init(token: LifecycleCancellationToken, completion: @escaping (PlaybackQueryResult) -> Void) {
            self.token = token
            self.completion = completion
        }

        func complete(_ result: PlaybackQueryResult) {
            lock.lock()
            guard !didComplete, !token.isCancelled else {
                lock.unlock()
                return
            }
            didComplete = true
            lock.unlock()
            completion(result)
        }
    }
}

#if os(macOS)
/// `/usr/bin/osascript` is invoked directly with a fixed `-e` source string;
/// no shell is created and no runtime strings are interpolated into the script.
public final class BoundedAppleScriptRunner: BoundedAppleScriptRunning {
    private let launchQueue: DispatchQueue
    private let timeoutQueue: DispatchQueue
    private let outputLimit: Int

    public init(
        outputLimit: Int = 8_192,
        launchQueue: DispatchQueue = DispatchQueue(label: "com.spacevisualizer.apple-script-launch", qos: .utility),
        timeoutQueue: DispatchQueue = DispatchQueue(label: "com.spacevisualizer.apple-script-timeout", qos: .utility)
    ) {
        self.outputLimit = max(1, outputLimit)
        self.launchQueue = launchQueue
        self.timeoutQueue = timeoutQueue
    }

    @discardableResult
    public func run(
        fixedScript: String,
        timeout: TimeInterval,
        completion: @escaping (Result<String, AppleScriptRunnerError>) -> Void
    ) -> LifecycleCancellationToken {
        let token = LifecycleCancellationToken()
        let execution = ProcessExecution(
            token: token,
            fixedScript: fixedScript,
            timeout: max(0.001, timeout),
            outputLimit: outputLimit,
            completion: completion
        )
        token.addCancellationHandler { execution.cancel() }
        launchQueue.async { execution.start(timeoutQueue: self.timeoutQueue) }
        return token
    }

    private final class ProcessExecution {
        private let lock = NSLock()
        private let token: LifecycleCancellationToken
        private let fixedScript: String
        private let timeout: TimeInterval
        private let outputLimit: Int
        private let completion: (Result<String, AppleScriptRunnerError>) -> Void
        private var process: Process?
        private var didFinish = false

        init(
            token: LifecycleCancellationToken,
            fixedScript: String,
            timeout: TimeInterval,
            outputLimit: Int,
            completion: @escaping (Result<String, AppleScriptRunnerError>) -> Void
        ) {
            self.token = token
            self.fixedScript = fixedScript
            self.timeout = timeout
            self.outputLimit = outputLimit
            self.completion = completion
        }

        func start(timeoutQueue: DispatchQueue) {
            guard !token.isCancelled else { return }
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-l", "AppleScript", "-e", fixedScript]
            process.standardOutput = stdout
            process.standardError = stderr

            lock.lock()
            self.process = process
            let canceledBeforeLaunch = token.isCancelled
            lock.unlock()
            guard !canceledBeforeLaunch else { return }

            do {
                try process.run()
            } catch {
                finish(.failure(.failed(error.localizedDescription)))
                return
            }

            timeoutQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.timeOut()
            }

            let group = DispatchGroup()
            let output = DataBox()
            let errors = DataBox()
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                output.set(Self.readBounded(stdout.fileHandleForReading, limit: self.outputLimit))
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                errors.set(Self.readBounded(stderr.fileHandleForReading, limit: self.outputLimit))
                group.leave()
            }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                process.waitUntilExit()
                group.wait()
                self?.processExited(process, output: output.value, errors: errors.value)
            }
        }

        func cancel() {
            lock.lock()
            if process?.isRunning == true { process?.terminate() }
            lock.unlock()
            finish(.failure(.canceled))
        }

        private func timeOut() {
            lock.lock()
            if process?.isRunning == true { process?.terminate() }
            lock.unlock()
            finish(.failure(.timedOut))
        }

        private func processExited(_ process: Process, output: Data, errors: Data) {
            guard output.count <= outputLimit, errors.count <= outputLimit else {
                finish(.failure(.outputExceededLimit))
                return
            }
            guard process.terminationStatus == 0 else {
                let message = String(data: errors, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = message?.isEmpty == false ? message! : "Music playback helper failed."
                if Self.isAutomationDenied(detail) {
                    finish(.failure(.automationDenied(detail)))
                } else {
                    finish(.failure(.failed(detail)))
                }
                return
            }
            guard let string = String(data: output, encoding: .utf8) else {
                finish(.failure(.failed("Music playback helper returned non-text output.")))
                return
            }
            finish(.success(string))
        }

        private func finish(_ result: Result<String, AppleScriptRunnerError>) {
            lock.lock()
            guard !didFinish else {
                lock.unlock()
                return
            }
            didFinish = true
            lock.unlock()
            completion(result)
        }

        private final class DataBox {
            private let lock = NSLock()
            private var storage = Data()

            func set(_ value: Data) {
                lock.lock()
                storage = value
                lock.unlock()
            }

            var value: Data {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }
        }

        private static func readBounded(_ handle: FileHandle, limit: Int) -> Data {
            var result = Data()
            while true {
                let chunk = handle.availableData
                guard !chunk.isEmpty else { break }
                let remaining = max(0, limit + 1 - result.count)
                if remaining > 0 { result.append(chunk.prefix(remaining)) }
            }
            return result
        }

        private static func isAutomationDenied(_ message: String) -> Bool {
            let lowercased = message.lowercased()
            return lowercased.contains("-1743") || lowercased.contains("not authorized") ||
                lowercased.contains("not permitted") || lowercased.contains("automation") && lowercased.contains("denied")
        }
    }
}
#else
public final class BoundedAppleScriptRunner: BoundedAppleScriptRunning {
    public init(outputLimit: Int = 8_192) {}

    @discardableResult
    public func run(
        fixedScript: String,
        timeout: TimeInterval,
        completion: @escaping (Result<String, AppleScriptRunnerError>) -> Void
    ) -> LifecycleCancellationToken {
        let token = LifecycleCancellationToken()
        DispatchQueue.global(qos: .utility).async {
            guard !token.isCancelled else { return }
            completion(.failure(.failed("Music playback helper is available only on macOS.")))
        }
        return token
    }
}
#endif
