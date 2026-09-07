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
    public static func balls(features: AudioFeatures, reduceMotion: Bool) -> [SpatialBall] {
        let p = VisualParameters(features: features)
        let levels = reduceMotion ? [0.0, 0.0, 0.0] :
            [Double(p.expansion), Double(p.deformation), Double(p.edgeDetail)]
        return (0..<28).map { index in
            let seed = Double(index)
            let depth = -0.9 + Double((index * 11) % 28) / 27 * 1.8
            let perspective = 3.5 / (3.5 - depth)
            let lane = -0.73 + Double((index * 9) % 28) / 27 * 1.46
            let energy = levels[index % 3]
            let floor = 0.28 + (depth + 0.9) * 0.25
            let lift = energy * (0.3 + Double(index % 5) * 0.085)
            let sway = sin(seed * 2.4) * levels[1] * 0.065
            return SpatialBall(x: (lane + sway) * perspective * 0.72,
                y: floor - lift * perspective, floorY: floor,
                depth: depth, radius: (0.012 + Double(index % 4) * 0.006) * perspective * (1 + energy * 0.3),
                energy: energy, palette: index % 3)
        }.sorted { $0.depth < $1.depth }
    }
}
