import Foundation

public struct CaptureTelemetrySnapshot: Equatable {
    public var callbacks: UInt64 = 0
    public var renderedFrames: UInt64 = 0
    public var lastRenderStatus: Int32 = 0

    public var summary: String {
        "Callbacks: \(callbacks) · rendered frames: \(renderedFrames) · render OSStatus: \(lastRenderStatus)"
    }
}

/// Best-effort diagnostic counters; the audio thread never waits for the UI.
public final class CaptureTelemetry {
    private let lock = NSLock()
    private var value = CaptureTelemetrySnapshot()

    public init() {}

    public func record(frames: UInt32, status: Int32) {
        guard lock.try() else { return }
        defer { lock.unlock() }
        value.callbacks &+= 1
        value.lastRenderStatus = status
        if status == 0 { value.renderedFrames &+= UInt64(frames) }
    }

    public func snapshot() -> CaptureTelemetrySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
