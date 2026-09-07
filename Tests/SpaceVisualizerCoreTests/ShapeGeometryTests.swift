import XCTest
@testable import SpaceVisualizerCore

final class ShapeGeometryTests: XCTestCase {
    func testCachedGeometryMatchesOriginalProjection() {
        var stale = AudioFeatures.fixtureLive
        stale.isFresh = false
        for reduced in [false, true] {
            for features in [AudioFeatures.settled, .fixtureLive, stale] {
                let policy = VisualPreviewPolicy(features: features, reduceMotion: reduced)
                let rings = ShapeGeometry.projectedRings(features: features, reduceMotion: reduced)
                XCTAssertEqual(rings.count, policy.ringCount)
                for ring in rings.indices {
                    XCTAssertEqual(rings[ring].count, policy.pointCount + 1)
                    for index in rings[ring].indices {
                        let expected = ShapeGeometry.point(
                            angle: Double(index) / Double(policy.pointCount) * 2 * .pi,
                            ring: ring, ringCount: policy.ringCount,
                            features: features, reduceMotion: reduced)
                        let actual = rings[ring][index]
                        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-12)
                        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-12)
                        XCTAssertEqual(actual.depth, expected.depth, accuracy: 1e-12)
                    }
                }
            }
        }
    }

    func testLiveAudioChangesProjectedGeometry() {
        let quiet = ShapeGeometry.point(angle: 0.7, ring: 2, ringCount: 13, features: .settled, reduceMotion: false)
        let live = ShapeGeometry.point(angle: 0.7, ring: 2, ringCount: 13, features: .fixtureLive, reduceMotion: false)
        XCTAssertNotEqual(quiet, live)
        XCTAssertTrue(live.x.isFinite && live.y.isFinite && live.depth.isFinite)
    }

    func testReducedMotionKeepsGeometryStatic() {
        let quiet = ShapeGeometry.point(angle: 0.7, ring: 2, ringCount: 7, features: .settled, reduceMotion: true)
        let live = ShapeGeometry.point(angle: 0.7, ring: 2, ringCount: 7, features: .fixtureLive, reduceMotion: true)
        XCTAssertEqual(quiet, live)
    }

    func testStaleAudioSettlesGeometry() {
        var stale = AudioFeatures.fixtureLive
        stale.isFresh = false
        XCTAssertEqual(
            ShapeGeometry.point(angle: 1, ring: 3, ringCount: 13, features: stale, reduceMotion: false),
            ShapeGeometry.point(angle: 1, ring: 3, ringCount: 13, features: .settled, reduceMotion: false))
    }
}
