import Foundation

/// Channel order is left/right only for stereo. Other layouts use symmetric downmix.
public struct StereoRegionLevels: Codable, Equatable, Sendable {
    public var left: [Float]
    public var right: [Float]

    public init(left: [Float], right: [Float]) {
        self.left = left
        self.right = right
    }
}

public enum StereoRegions {
    public static let edges: [Double] = [20, 60, 110, 180, 250, 400, 650, 1_000,
                                        1_600, 2_500, 4_000, 6_000, 9_000, 12_000, 16_000]
    public static let count = edges.count - 1

    public static func palette(for region: Int) -> Int {
        region < 4 ? 0 : (region < 10 ? 1 : 2)
    }

    public static func attack(for region: Int) -> Float {
        [Float(0.7), 0.6, 0.85][palette(for: region)]
    }

    public static func release(for region: Int) -> Float {
        [Float(0.14), 0.2, 0.35][palette(for: region)]
    }

    public static func level(_ values: [Float], at index: Int) -> Float {
        guard values.indices.contains(index), values[index].isFinite else { return 0 }
        return min(1, max(0, values[index]))
    }
}
