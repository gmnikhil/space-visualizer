import XCTest
@testable import SpaceVisualizerCore

final class MusicPlaybackQueryTests: XCTestCase {
    func testAbsentMusicCompletesWithoutRunningTheScriptOrLaunchingMusic() {
        let presence = FakeMusicProcessPresence(isRunning: false)
        let runner = FakeAppleScriptRunner()
        let query = MusicPlaybackQueryAdapter(presence: presence, runner: runner)
        let received = expectation(description: "Absent Music result")
        var result: PlaybackQueryResult?

        _ = query.query {
            result = $0
            received.fulfill()
        }

        wait(for: [received], timeout: 1)
        XCTAssertEqual(result, .success(PlaybackObservation(state: .stopped, isPlayerAvailable: false)))
        XCTAssertEqual(presence.checkCount, 1)
        XCTAssertEqual(runner.runCount, 0)
    }

    func testPlayerStateIsReadableWithoutACurrentTrack() {
        let runner = FakeAppleScriptRunner()
        let query = MusicPlaybackQueryAdapter(
            presence: FakeMusicProcessPresence(isRunning: true),
            runner: runner
        )
        let received = expectation(description: "Parsed observation")
        var result: PlaybackQueryResult?

        _ = query.query {
            result = $0
            received.fulfill()
        }
        waitForRunner(runner)
        runner.complete(.success("playing\u{1F}\u{1F}\u{1F}\u{1F}\u{1F}\u{1F}"))

        wait(for: [received], timeout: 1)
        XCTAssertEqual(result, .success(PlaybackObservation(state: .playing, track: TrackSnapshot(playbackState: .playing))))
    }

    func testOptionalTrackPropertiesAreParsedIndependently() {
        let runner = FakeAppleScriptRunner()
        let query = MusicPlaybackQueryAdapter(
            presence: FakeMusicProcessPresence(isRunning: true),
            runner: runner
        )
        let received = expectation(description: "Parsed optional fields")
        var result: PlaybackQueryResult?

        _ = query.query {
            result = $0
            received.fulfill()
        }
        waitForRunner(runner)
        runner.complete(.success("paused\u{1F}  Title  \u{1F}\u{1F} Album \u{1F}not-a-number\u{1F}0\u{1F}true"))

        wait(for: [received], timeout: 1)
        guard case let .success(observation)? = result else {
            return XCTFail("Expected a parsed playback observation")
        }
        XCTAssertEqual(observation.state, .paused)
        XCTAssertEqual(observation.track?.title, "Title")
        XCTAssertNil(observation.track?.artist)
        XCTAssertEqual(observation.track?.album, "Album")
        XCTAssertNil(observation.track?.position)
        XCTAssertNil(observation.track?.duration)
        XCTAssertEqual(observation.track?.artworkAvailable, true)
    }

    func testMalformedOutputFailsInsteadOfInventingPlayback() {
        let runner = FakeAppleScriptRunner()
        let query = MusicPlaybackQueryAdapter(
            presence: FakeMusicProcessPresence(isRunning: true),
            runner: runner
        )
        let received = expectation(description: "Malformed output")
        var result: PlaybackQueryResult?

        _ = query.query {
            result = $0
            received.fulfill()
        }
        waitForRunner(runner)
        runner.complete(.success("playing\u{1F}only-one-track-field"))

        wait(for: [received], timeout: 1)
        XCTAssertEqual(result, .failed("Music returned a malformed playback response."))
    }

    func testDeniedTimedOutAndCanceledScriptResultsRemainDistinct() {
        let fixtures: [(Result<String, AppleScriptRunnerError>, PlaybackQueryResult)] = [
            (.failure(.automationDenied("Automation denied")), .denied("Automation denied")),
            (.failure(.timedOut), .timedOut),
            (.failure(.canceled), .canceled)
        ]

        for (runnerResult, expected) in fixtures {
            let runner = FakeAppleScriptRunner()
            let query = MusicPlaybackQueryAdapter(
                presence: FakeMusicProcessPresence(isRunning: true),
                runner: runner
            )
            let received = expectation(description: "Mapped \(expected)")
            var result: PlaybackQueryResult?

            _ = query.query {
                result = $0
                received.fulfill()
            }
            waitForRunner(runner)
            runner.complete(runnerResult)
            wait(for: [received], timeout: 1)
            XCTAssertEqual(result, expected)
        }
    }

    func testCanceledOuterQueryDiscardsItsObsoleteLaterCompletion() {
        let runner = FakeAppleScriptRunner()
        let query = MusicPlaybackQueryAdapter(
            presence: FakeMusicProcessPresence(isRunning: true),
            runner: runner
        )
        let noCompletion = expectation(description: "No obsolete completion")
        noCompletion.isInverted = true

        let token = query.query { _ in noCompletion.fulfill() }
        waitForRunner(runner)
        token.cancel()
        runner.complete(.success("playing\u{1F}\u{1F}\u{1F}\u{1F}\u{1F}\u{1F}"))

        wait(for: [noCompletion], timeout: 0.1)
    }

    func testAdapterUsesOneSecondTimeoutAndOnlyItsFixedScript() {
        let runner = FakeAppleScriptRunner()
        let query = MusicPlaybackQueryAdapter(
            presence: FakeMusicProcessPresence(isRunning: true),
            runner: runner
        )

        _ = query.query { _ in }
        waitForRunner(runner)

        XCTAssertEqual(runner.timeout, 1)
        XCTAssertEqual(runner.script, MusicPlaybackQueryAdapter.fixedScript)
        XCTAssertFalse(runner.script?.contains("$") ?? true)
        XCTAssertTrue(MusicPlaybackQueryAdapter.fixedScript.contains("player state"))
        XCTAssertTrue(MusicPlaybackQueryAdapter.fixedScript.contains("try"))
    }

    private func waitForRunner(_ runner: FakeAppleScriptRunner, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(runner.waitForRun(), "AppleScript runner was not invoked", file: file, line: line)
    }
}

private final class FakeMusicProcessPresence: MusicProcessPresenceChecking {
    var isRunning: Bool
    private(set) var checkCount = 0

    init(isRunning: Bool) { self.isRunning = isRunning }

    func isMusicRunning() -> Bool {
        checkCount += 1
        return isRunning
    }
}

private final class FakeAppleScriptRunner: BoundedAppleScriptRunning {
    private(set) var runCount = 0
    private(set) var script: String?
    private(set) var timeout: TimeInterval?
    private let runSignal = DispatchSemaphore(value: 0)
    private var completion: ((Result<String, AppleScriptRunnerError>) -> Void)?

    @discardableResult
    func run(
        fixedScript: String,
        timeout: TimeInterval,
        completion: @escaping (Result<String, AppleScriptRunnerError>) -> Void
    ) -> LifecycleCancellationToken {
        runCount += 1
        script = fixedScript
        self.timeout = timeout
        self.completion = completion
        runSignal.signal()
        return LifecycleCancellationToken()
    }

    func complete(_ result: Result<String, AppleScriptRunnerError>) {
        completion?(result)
    }

    func waitForRun() -> Bool {
        runSignal.wait(timeout: .now() + 1) == .success
    }
}
