import Foundation

public struct SpatialBall: Equatable {
    public let x: Double
    public let y: Double
    public let floorY: Double
    public let depth: Double
    public let radius: Double
    public let energy: Double
    public let palette: Int
}

/// Deterministic spatial layout. Displacement comes from audio, never a clock.
public enum SpatialScene {
    /// Static clearance keeps short trails from collapsing against their floor anchor.
    public static let restingLift = 0.12

    public static func balls(features: AudioFeatures, reduceMotion: Bool) -> [SpatialBall] {
        let p = VisualParameters(features: features)
        let fallback = [Double(p.expansion), Double(p.deformation), Double(p.edgeDetail)]
        let active = !reduceMotion && features.isFresh && !features.isSilent
        return (0..<(StereoRegions.count * 2)).map { index in
            let region = index / 2
            let isLeft = index % 2 == 0
            let palette = StereoRegions.palette(for: region)
            let depth = -0.9 + Double((region * 11) % StereoRegions.count) / 13 * 1.8
            let perspective = 3.5 / (3.5 - depth)
            let lane = 0.12 + Double((region * 9) % StereoRegions.count) / 13 * 0.61
            let energy: Double
            if !active {
                energy = 0
            } else if let stereo = features.stereoRegions {
                energy = Double(StereoRegions.level(isLeft ? stereo.left : stereo.right, at: region))
            } else {
                energy = fallback[palette]
            }
            let floor = 0.28 + (depth + 0.9) * 0.25
            let lift = restingLift + energy * (0.3 + Double(region % 5) * 0.085)
            return SpatialBall(x: (isLeft ? -lane : lane) * perspective * 0.72,
                y: floor - lift * perspective, floorY: floor,
                depth: depth, radius: (0.012 + Double(region % 4) * 0.006) * perspective * (1 + energy * 0.3),
                energy: energy, palette: palette)
        }.sorted { $0.depth < $1.depth }
    }
}
