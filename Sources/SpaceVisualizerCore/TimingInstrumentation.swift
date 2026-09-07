import Foundation
#if os(macOS)
import Darwin
#endif

public struct LatencySummary: Codable, Equatable, Sendable {
    public let samples: UInt64
    public let p50Nanoseconds: UInt64?
    public let p95Nanoseconds: UInt64?
    public let maximumNanoseconds: UInt64?

    public init(
        samples: UInt64 = 0,
        p50Nanoseconds: UInt64? = nil,
        p95Nanoseconds: UInt64? = nil,
        maximumNanoseconds: UInt64? = nil
    ) {
        self.samples = samples
        self.p50Nanoseconds = p50Nanoseconds
        self.p95Nanoseconds = p95Nanoseconds
        self.maximumNanoseconds = maximumNanoseconds
    }

    public static let empty = LatencySummary()
}

/// Fixed logarithmic buckets keep instrumentation bounded and suitable for a
/// real-time-adjacent callback. Percentiles are intentionally approximate.
struct BoundedLatencyHistogram: Sendable {
    private static let upperBounds: [UInt64] = [
        1_000, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000,
        1_000_000, 2_500_000, 5_000_000, 10_000_000, 25_000_000,
        50_000_000, 100_000_000, UInt64.max
    ]

    private var buckets = Array(repeating: UInt64.zero, count: Self.upperBounds.count)
    private var sampleCount: UInt64 = 0
    private var maximum: UInt64 = 0

    mutating func record(_ value: UInt64) {
        let index = Self.upperBounds.firstIndex { value <= $0 } ?? Self.upperBounds.count - 1
        buckets[index] &+= 1
        sampleCount &+= 1
        maximum = max(maximum, value)
    }

    func snapshot() -> LatencySummary {
        guard sampleCount > 0 else { return .empty }
        return LatencySummary(
            samples: sampleCount,
            p50Nanoseconds: valueAtPercentile(0.50),
            p95Nanoseconds: valueAtPercentile(0.95),
            maximumNanoseconds: maximum
        )
    }

    private func valueAtPercentile(_ percentile: Double) -> UInt64 {
        let target = max(UInt64(1), UInt64(ceil(Double(sampleCount) * percentile)))
        var accumulated: UInt64 = 0
        for (index, count) in buckets.enumerated() {
            accumulated &+= count
            if accumulated >= target { return Self.upperBounds[index] }
        }
        return maximum
    }
}

public struct AnalysisTelemetrySnapshot: Equatable, Sendable {
    public let analysisDuration: LatencySummary
    public let mailboxAge: LatencySummary
    public let workerStarts: UInt64
    public let workerStops: UInt64
    public let activeWorkers: UInt64
    public let activeTasks: UInt64

    public init(
        analysisDuration: LatencySummary = .empty,
        mailboxAge: LatencySummary = .empty,
        workerStarts: UInt64 = 0,
        workerStops: UInt64 = 0,
        activeWorkers: UInt64 = 0,
        activeTasks: UInt64 = 0
    ) {
        self.analysisDuration = analysisDuration
        self.mailboxAge = mailboxAge
        self.workerStarts = workerStarts
        self.workerStops = workerStops
        self.activeWorkers = activeWorkers
        self.activeTasks = activeTasks
    }
}

/// Bounded metrics for one analysis worker. It contains no PCM or artwork.
public final class AnalysisTelemetry: @unchecked Sendable {
    private let lock = NSLock()
    private var analysisDurations = BoundedLatencyHistogram()
    private var mailboxAges = BoundedLatencyHistogram()
    private var starts: UInt64 = 0
    private var stops: UInt64 = 0
    private var active: UInt64 = 0

    public init() {}

    func recordAnalysis(durationNanoseconds: UInt64, mailboxAgeNanoseconds: UInt64?) {
        lock.lock()
        analysisDurations.record(durationNanoseconds)
        if let mailboxAgeNanoseconds { mailboxAges.record(mailboxAgeNanoseconds) }
        lock.unlock()
    }

    func recordWorkerStarted() {
        lock.lock()
        starts &+= 1
        active &+= 1
        lock.unlock()
    }

    func recordWorkerStopped() {
        lock.lock()
        stops &+= 1
        active = active > 0 ? active - 1 : 0
        lock.unlock()
    }

    public func snapshot() -> AnalysisTelemetrySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return AnalysisTelemetrySnapshot(
            analysisDuration: analysisDurations.snapshot(),
            mailboxAge: mailboxAges.snapshot(),
            workerStarts: starts,
            workerStops: stops,
            activeWorkers: active,
            activeTasks: active
        )
    }
}

public struct ProcessResourceSnapshot: Equatable, Sendable {
    public let residentMemoryBytes: UInt64?
    public let activeAnalysisWorkers: UInt64
    public let activeAnalysisTasks: UInt64

    public init(
        residentMemoryBytes: UInt64?,
        activeAnalysisWorkers: UInt64,
        activeAnalysisTasks: UInt64
    ) {
        self.residentMemoryBytes = residentMemoryBytes
        self.activeAnalysisWorkers = activeAnalysisWorkers
        self.activeAnalysisTasks = activeAnalysisTasks
    }
}

public enum ProcessResourceSampler {
    public static func snapshot(analysis: AnalysisTelemetry) -> ProcessResourceSnapshot {
        let analysisSnapshot = analysis.snapshot()
        return ProcessResourceSnapshot(
            residentMemoryBytes: residentMemoryBytes(),
            activeAnalysisWorkers: analysisSnapshot.activeWorkers,
            activeAnalysisTasks: analysisSnapshot.activeTasks
        )
    }

    private static func residentMemoryBytes() -> UInt64? {
#if os(macOS)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.resident_size
#else
        return nil
#endif
    }
}
