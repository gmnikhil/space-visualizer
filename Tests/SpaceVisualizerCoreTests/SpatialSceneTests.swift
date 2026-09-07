import XCTest
@testable import SpaceVisualizerCore

final class SpatialSceneTests: XCTestCase {
    func testSceneIsBoundedAndSortedBackToFront() {
        let balls = SpatialScene.balls(features: .fixtureLive, reduceMotion: false)
        XCTAssertEqual(balls.count, 28)
        XCTAssertEqual(balls.map(\.depth), balls.map(\.depth).sorted())
        XCTAssertTrue(balls.allSatisfy { abs($0.x) < 1 && abs($0.y) < 1 && $0.radius > 0 && $0.radius < 0.1 })
    }

    func testAudioLiftsBallsAndSilenceSettlesThem() {
        let quiet = SpatialScene.balls(features: .settled, reduceMotion: false)
        XCTAssertNotEqual(quiet, SpatialScene.balls(features: .fixtureLive, reduceMotion: false))
        var stale = AudioFeatures.fixtureLive
        stale.isFresh = false
        XCTAssertEqual(quiet, SpatialScene.balls(features: stale, reduceMotion: false))
    }

    func testReducedMotionRemovesAudioDrivenDisplacement() {
        XCTAssertEqual(SpatialScene.balls(features: .settled, reduceMotion: true),
                       SpatialScene.balls(features: .fixtureLive, reduceMotion: true))
    }
}
