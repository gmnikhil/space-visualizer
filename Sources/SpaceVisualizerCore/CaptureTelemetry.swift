import Foundation

public struct CaptureTelemetrySnapshot: Equatable {
    public var callbacks: UInt64 = 0
    public var renderedFrames: UInt64 = 0
    public var lastRenderStatus: Int32 = 0
    public var callbackAge: LatencySummary = .empty

    public var summary: String {
        let age = callbackAge.samples == 0
            ? "callback age: —"
            : "callback age p50/p95: \(callbackAge.p50Nanoseconds ?? 0)/\(callbackAge.p95Nanoseconds ?? 0) ns"
        return "Callbacks: \(callbacks) · rendered frames: \(renderedFrames) · render OSStatus: \(lastRenderStatus) · \(age)"
    }
}

/// Best-effort diagnostic counters; the audio thread never waits for the UI.
public final class CaptureTelemetry {
    private let lock = NSLock()
    private var value = CaptureTelemetrySnapshot()
    private var callbackAges = BoundedLatencyHistogram()

    public init() {}

    /// The callback uses a try-lock and fixed histogram storage. Missing a
    /// diagnostic sample is preferable to making audio wait for the UI.
    public func record(
        frames: UInt32,
        status: Int32,
        callbackAgeNanoseconds: UInt64? = nil
    ) {
        guard lock.try() else { return }
        value.callbacks &+= 1
        value.lastRenderStatus = status
        if status == 0 { value.renderedFrames &+= UInt64(frames) }
        if let callbackAgeNanoseconds { callbackAges.record(callbackAgeNanoseconds) }
        lock.unlock()
    }

    public func snapshot() -> CaptureTelemetrySnapshot {
        lock.lock()
        defer { lock.unlock() }
        var result = value
        result.callbackAge = callbackAges.snapshot()
        return result
    }
}
