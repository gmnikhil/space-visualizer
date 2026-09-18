#if os(macOS)
import XCTest
@testable import SpaceVisualizerCore

final class BoundedAppleScriptRunnerTests: XCTestCase {
    func testSuccessfulHelperReleasesCompletionEvenWhenTokenIsRetained() {
        assertReleasesCompletion(script: "return \"ready\"", expected: .success("ready\n"))
    }

    func testOversizedOutputReleasesCompletion() {
        assertReleasesCompletion(
            script: "return \"too long\"", outputLimit: 4,
            expected: .failure(.outputExceededLimit)
        )
    }

    func testTimedOutHelperReleasesCompletion() {
        assertReleasesCompletion(script: "delay 5", timeout: 0.1, expected: .failure(.timedOut))
    }

    func testCanceledHelperReleasesCompletion() {
        assertReleasesCompletion(script: "delay 5", cancel: true, expected: .failure(.canceled))
    }

    func testHelperFinishesWhenCallerDiscardsCancellationToken() {
        let runner = BoundedAppleScriptRunner()
        let completed = expectation(description: "Execution owns itself until exit")
        _ = runner.run(fixedScript: "delay 0.1\nreturn \"ready\"", timeout: 2) {
            XCTAssertEqual($0, .success("ready\n"))
            completed.fulfill()
        }
        wait(for: [completed], timeout: 3)
    }

    func testCancellationBeforeLaunchDoesNotRunScriptOrCompleteTwice() {
        let launchQueue = DispatchQueue(label: "test.script-launch")
        launchQueue.suspend()
        let runner = BoundedAppleScriptRunner(launchQueue: launchQueue)
        let completed = expectation(description: "Canceled before launch")
        completed.assertForOverFulfill = true
        let token = runner.run(fixedScript: "return \"should not run\"", timeout: 2) {
            XCTAssertEqual($0, .failure(.canceled))
            completed.fulfill()
        }
        token.cancel()
        launchQueue.resume()
        launchQueue.sync {}
        wait(for: [completed], timeout: 3)
    }

    private func assertReleasesCompletion(
        script: String,
        timeout: TimeInterval = 2,
        outputLimit: Int = 8_192,
        cancel: Bool = false,
        expected: Result<String, AppleScriptRunnerError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let runner = BoundedAppleScriptRunner(outputLimit: outputLimit)
        let completed = expectation(description: "Helper completed once")
        completed.assertForOverFulfill = true
        let released = expectation(description: "Completion capture released")
        // Keeping the token alive reproduces the old token -> execution ->
        // completion retention, even after a successful helper has exited.
        let token: LifecycleCancellationToken = {
            let probe = ReleaseProbe { released.fulfill() }
            return runner.run(fixedScript: script, timeout: timeout) { [probe] result in
                withExtendedLifetime(probe) {
                    XCTAssertEqual(result, expected, file: file, line: line)
                    completed.fulfill()
                }
            }
        }()
        if cancel { token.cancel() }
        withExtendedLifetime(token) {
            wait(for: [completed, released], timeout: 4)
        }
    }
}

private final class ReleaseProbe {
    private let onRelease: () -> Void
    init(onRelease: @escaping () -> Void) { self.onRelease = onRelease }
    deinit { onRelease() }
}
#endif
