import Foundation

public struct DisplayTelemetrySnapshot: Codable, Equatable, Sendable {
    public let frameWork: LatencySummary

    public init(frameWork: LatencySummary = .empty) {
        self.frameWork = frameWork
    }
}

/// Fixed-size, audio-free timing telemetry for the display callback. It does
/// not publish ObservableObject changes and therefore cannot invalidate the
/// surrounding window once per frame.
public final class DisplayFrameTelemetry: @unchecked Sendable {
    private let lock = NSLock()
    private var frameWork = BoundedLatencyHistogram()

    public init() {}

    public func recordFrame(workNanoseconds: UInt64) {
        lock.lock()
        frameWork.record(workNanoseconds)
        lock.unlock()
    }

    public func snapshot() -> DisplayTelemetrySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return DisplayTelemetrySnapshot(frameWork: frameWork.snapshot())
    }
}
