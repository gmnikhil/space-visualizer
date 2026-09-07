import Foundation
@testable import SpaceVisualizerCore

final class FakeMusicQuery: MusicQuerying {
    var response: Result<RawMusicSnapshot, Error> = .success(.unknown)
    private(set) var queryCount = 0

    func query() throws -> RawMusicSnapshot {
        queryCount += 1
        return try response.get()
    }
}

final class FakeCaptureResources: CaptureResourceLifecycle {
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var destroys = 0
    var startError: Error?

    func start() throws {
        starts += 1
        if let startError { throw startError }
    }

    func stop() {
        stops += 1
    }

    func destroy() {
        destroys += 1
    }
}

final class FakeClock: SpaceVisualizerClock {
    var now: UInt64 = 0
    func uptimeNanoseconds() -> UInt64 { now }
}

struct FixtureError: Error, Equatable {}
