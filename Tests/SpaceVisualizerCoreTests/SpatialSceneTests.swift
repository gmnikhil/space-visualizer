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

    func testRestingClearanceDoesNotInventEnergyOrClampQuietReactions() {
        let quiet = SpatialScene.balls(features: .settled, reduceMotion: false)
        XCTAssertTrue(quiet.allSatisfy { $0.y < $0.floorY && $0.energy == 0 })
        for ball in quiet {
            let perspective = 3.5 / (3.5 - ball.depth)
            XCTAssertEqual(ball.floorY - ball.y, SpatialScene.restingLift * perspective, accuracy: 0.000001)
        }
        var low = AudioFeatures.fixtureLive
        low.stereoRegions = StereoRegionLevels(
            left: Array(repeating: 0.04, count: StereoRegions.count),
            right: Array(repeating: 0.04, count: StereoRegions.count))
        let lifted = SpatialScene.balls(features: low, reduceMotion: false)
        for (resting, reacting) in zip(quiet, lifted) {
            XCTAssertLessThan(reacting.y, resting.y)
            XCTAssertEqual(reacting.x, resting.x)
            XCTAssertEqual(reacting.energy, Double(Float(0.04)))
        }
        XCTAssertEqual(SpatialScene.balls(features: low, reduceMotion: true), quiet)
    }

    func testReducedMotionRemovesAudioDrivenDisplacement() {
        XCTAssertEqual(SpatialScene.balls(features: .settled, reduceMotion: true),
                       SpatialScene.balls(features: .fixtureLive, reduceMotion: true))
    }
}
