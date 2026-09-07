import Foundation
#if os(macOS)
import Darwin
#endif

/// Converts Core Audio host timestamps into the monotonic nanosecond domain
/// used by freshness and latency checks. The protocol keeps the conversion
/// injectable for deterministic tests.
public protocol AudioTimestampClock: AnyObject {
    func nowNanoseconds() -> UInt64
    func nanoseconds(for timestamp: UInt64) -> UInt64?
    func timestamp(forNanoseconds nanoseconds: UInt64) -> UInt64?
    func ageNanoseconds(of timestamp: UInt64, nowNanoseconds: UInt64) -> UInt64?
}

public final class SystemAudioTimestampClock: AudioTimestampClock, @unchecked Sendable {
#if os(macOS)
    private let numer: UInt64
    private let denom: UInt64
#endif

    public init() {
#if os(macOS)
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        numer = UInt64(timebase.numer)
        denom = max(1, UInt64(timebase.denom))
#endif
    }

    public func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    public func nanoseconds(for timestamp: UInt64) -> UInt64? {
        guard timestamp > 0 else { return nil }
#if os(macOS)
        let quotient = timestamp / denom
        let remainder = timestamp % denom
        let (whole, wholeOverflow) = quotient.multipliedReportingOverflow(by: numer)
        let (fraction, fractionOverflow) = remainder.multipliedReportingOverflow(by: numer)
        guard !wholeOverflow, !fractionOverflow else { return nil }
        return whole &+ fraction / denom
#else
        return timestamp
#endif
    }

    public func timestamp(forNanoseconds nanoseconds: UInt64) -> UInt64? {
#if os(macOS)
        let quotient = nanoseconds / numer
        let remainder = nanoseconds % numer
        let (whole, wholeOverflow) = quotient.multipliedReportingOverflow(by: denom)
        let (fraction, fractionOverflow) = remainder.multipliedReportingOverflow(by: denom)
        guard !wholeOverflow, !fractionOverflow else { return nil }
        return whole &+ fraction / numer
#else
        return nanoseconds
#endif
    }

    public func ageNanoseconds(of timestamp: UInt64, nowNanoseconds: UInt64) -> UInt64? {
        guard let sampleNanoseconds = nanoseconds(for: timestamp) else { return nil }
        return nowNanoseconds >= sampleNanoseconds ? nowNanoseconds - sampleNanoseconds : 0
    }
}

public enum AudioTiming {
    public static let maximumFreshSampleAgeNanoseconds: UInt64 = 250_000_000
    public static let smoothingReferenceIntervalNanoseconds: UInt64 = 16_000_000
}
