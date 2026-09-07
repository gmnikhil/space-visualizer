import Foundation

/// Pure, audio-driven 3D geometry for the feasibility preview.
public struct ShapePoint: Equatable {
    public let x: Double
    public let y: Double
    public let depth: Double
}

public enum ShapeGeometry {
    private struct VertexSeed {
        let x: Double
        let y: Double
        let z: Double
        let deformation: Double
        let detail: Double
    }

    // Immutable, bounded caches; no cache growth with playback duration.
    private static let regularTopology = topology(reduceMotion: false)
    private static let reducedTopology = topology(reduceMotion: true)
    private static let tiltCos = cos(0.4)
    private static let tiltSin = sin(0.4)

    private static func topology(reduceMotion: Bool) -> [[VertexSeed]] {
        let policy = VisualPreviewPolicy(features: .settled, reduceMotion: reduceMotion)
        return (0..<policy.ringCount).map { ring in
            let orientation = Double(ring) / Double(policy.ringCount) * Double.pi
            return (0...policy.pointCount).map { index in
                let angle = Double(index) / Double(policy.pointCount) * 2 * Double.pi
                return VertexSeed(x: cos(angle), y: sin(angle) * cos(orientation),
                    z: sin(angle) * sin(orientation),
                    deformation: sin(angle * 3 + orientation), detail: cos(angle * 9))
            }
        }
    }

    public static func projectedRings(features: AudioFeatures, reduceMotion: Bool) -> [[ShapePoint]] {
        let p = VisualParameters(features: features)
        let bass = reduceMotion ? 0 : Double(p.expansion)
        let mids = reduceMotion ? 0 : Double(p.deformation)
        let highs = reduceMotion ? 0 : Double(p.edgeDetail)
        let yawCos = cos(0.55 + mids * 0.45)
        let yawSin = sin(0.55 + mids * 0.45)
        let seeds = reduceMotion ? reducedTopology : regularTopology
        return seeds.map { ring in
            ring.map { seed in
                let radius = (0.75 + bass * 0.55) *
                    (1 + mids * 0.22 * seed.deformation + highs * 0.04 * seed.detail)
                let x = radius * seed.x
                let y = radius * seed.y
                let z = radius * seed.z
                let rx = x * yawCos + z * yawSin
                let rz = -x * yawSin + z * yawCos
                let ry = y * tiltCos - rz * tiltSin
                let depth = y * tiltSin + rz * tiltCos
                let perspective = 3.8 / (3.8 - depth)
                return ShapePoint(x: rx * perspective, y: ry * perspective, depth: depth)
            }
        }
    }

    public static func point(angle: Double, ring: Int, ringCount: Int,
                             features: AudioFeatures, reduceMotion: Bool) -> ShapePoint {
        let p = VisualParameters(features: features)
        let motion = reduceMotion ? 0.0 : 1.0
        let bass = Double(p.expansion) * motion
        let mids = Double(p.deformation) * motion
        let highs = Double(p.edgeDetail) * motion
        let orientation = Double(ring) / Double(max(1, ringCount)) * Double.pi
        let radius = (0.75 + bass * 0.55) *
            (1 + mids * 0.22 * sin(angle * 3 + orientation) + highs * 0.04 * cos(angle * 9))
        let x = radius * cos(angle)
        let y = radius * sin(angle) * cos(orientation)
        let z = radius * sin(angle) * sin(orientation)
        // Fixed camera tilt plus bounded audio-driven orientation, not elapsed time.
        let yaw = 0.55 + mids * 0.45
        let rx = x * cos(yaw) + z * sin(yaw)
        let rz = -x * sin(yaw) + z * cos(yaw)
        let ry = y * cos(0.4) - rz * sin(0.4)
        let depth = y * sin(0.4) + rz * cos(0.4)
        let perspective = 3.8 / (3.8 - depth)
        return ShapePoint(x: rx * perspective, y: ry * perspective, depth: depth)
    }
}
