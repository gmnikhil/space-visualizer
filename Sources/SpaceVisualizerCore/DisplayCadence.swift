import Foundation

public enum DisplayCadencePolicy {
    public static let maximumRequestedFramesPerSecond = 120

    /// Core Animation still selects the actual cadence supported by the
    /// destination display. A 60 Hz display therefore remains 60 Hz.
    public static func preferredFramesPerSecond(displayMaximum: Int?) -> Int {
        guard let displayMaximum, displayMaximum > 0 else {
            return maximumRequestedFramesPerSecond
        }
        return min(maximumRequestedFramesPerSecond, displayMaximum)
    }
}

/// Controls diagnostic/status publication independently from the display link.
/// The renderer may consume every latest feature while the surrounding UI is
/// updated at no more than four times per second.
public struct DiagnosticUpdateLimiter: Sendable {
    public let minimumIntervalNanoseconds: UInt64
    private var lastPublicationNanoseconds: UInt64?

    public init(minimumIntervalNanoseconds: UInt64 = 250_000_000) {
        self.minimumIntervalNanoseconds = max(1, minimumIntervalNanoseconds)
    }

    public mutating func shouldPublish(at nowNanoseconds: UInt64) -> Bool {
        guard let lastPublicationNanoseconds else {
            self.lastPublicationNanoseconds = nowNanoseconds
            return true
        }
        guard nowNanoseconds >= lastPublicationNanoseconds,
              nowNanoseconds - lastPublicationNanoseconds >= minimumIntervalNanoseconds else {
            return false
        }
        self.lastPublicationNanoseconds = nowNanoseconds
        return true
    }

    public mutating func reset() {
        lastPublicationNanoseconds = nil
    }
}
