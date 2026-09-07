import Foundation

public enum CoreAudioCaptureError: Error, Equatable, LocalizedError, Sendable {
    case osStatus(Int32, String)
    case invalidFormat(String)
    case noMusicSource
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case let .osStatus(status, message): return "\(message) (OSStatus \(status))"
        case let .invalidFormat(message): return message
        case .noMusicSource: return "The Music audio source could not be resolved."
        case .unsupportedPlatform: return "Core Audio capture is available only on macOS."
        }
    }
}

#if os(macOS)
import CoreAudio

/// A local, nonmuting Music-only process tap. It creates one private aggregate
/// containing that tap and reads it through `AudioDeviceIOProc`; there is no
/// legacy render-unit or all-system-audio fallback.
public final class CoreAudioProcessTapCapture: CaptureResourceLifecycle {
    public let collector: PCMBufferCollector
    public let route: AudioRouteFacts
    public private(set) var format: AudioFormatFacts?
    public private(set) var generation: UInt64
    public let telemetry = CaptureTelemetry()

    private let aggregateName: String
    private let tapPolicy: ProcessTapPolicy
    private let clock: AudioTimestampClock
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var directInput: DirectTapInput?
    private var isDestroyed = false
    private var isStarted = false

    public init(
        route: AudioRouteFacts,
        collector: PCMBufferCollector,
        generation: UInt64 = 1,
        aggregateName: String = "Space Visualizer Music Tap",
        clock: AudioTimestampClock = SystemAudioTimestampClock()
    ) {
        self.route = route
        self.collector = collector
        self.generation = generation
        self.aggregateName = aggregateName
        self.tapPolicy = .music(routeID: route.id)
        self.clock = clock
    }

    deinit { destroy() }

    public func start() throws {
        guard !isDestroyed else {
            throw CoreAudioCaptureError.osStatus(-1, "Capture resource was already destroyed.")
        }
        guard !isStarted else { return }
        do {
            try createTapAndAggregate()
            let input = try DirectTapInput(
                device: aggregateID,
                tap: tapID,
                collector: collector,
                telemetry: telemetry,
                generation: generation,
                clock: clock
            )
            directInput = input
            format = input.format
            try input.start()
            isStarted = true
        } catch {
            destroy()
            throw error
        }
    }

    public func stop() {
        directInput?.stop()
        directInput = nil
        isStarted = false
    }

    public func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true
        stop()
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            if #available(macOS 14.2, *) {
                _ = AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        format = nil
        collector.reset(generation: generation &+ 1)
    }

    /// Invalidates pending PCM before the coordinator releases this session.
    public func invalidateForRouteChange() {
        generation &+= 1
        collector.reset(generation: generation)
    }

    private func createTapAndAggregate() throws {
        guard #available(macOS 14.2, *) else {
            throw CoreAudioCaptureError.unsupportedPlatform
        }
        guard let musicProcess = processObjectID(for: tapPolicy.targetBundleIdentifier) else {
            throw CoreAudioCaptureError.noMusicSource
        }

        let tapDescription = CATapDescription()
        tapDescription.name = aggregateName
        tapDescription.processes = [musicProcess]
        tapDescription.isPrivate = tapPolicy.isPrivate
        tapDescription.isExclusive = tapPolicy.isExclusive
        tapDescription.isMixdown = tapPolicy.isMixdown
        tapDescription.isMono = tapPolicy.isMono
        tapDescription.muteBehavior = .unmuted
        tapDescription.deviceUID = tapPolicy.routeID

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard tapStatus == noErr else {
            throw CoreAudioCaptureError.osStatus(
                tapStatus,
                "Could not create the Music process tap. Check system-audio permission."
            )
        }
        tapID = newTapID

        let tapUID = try uid(for: newTapID)
        let aggregateUID = "com.spacevisualizer.aggregate.\(UUID().uuidString)"
        let tapEntry: [String: Any] = [kAudioSubTapUIDKey: tapUID]
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: aggregateName,
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [tapEntry]
        ]

        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregateID)
        guard aggregateStatus == noErr else {
            throw CoreAudioCaptureError.osStatus(
                aggregateStatus,
                "Could not create the private Music tap aggregate device."
            )
        }
        aggregateID = newAggregateID
    }

    private func processObjectID(for bundleIdentifier: String) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioObjectID>.size) else { return nil }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioObjectID>.alignment
        )
        defer { raw.deallocate() }
        let processIDs = raw.assumingMemoryBound(to: AudioObjectID.self)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, processIDs) == noErr else {
            return nil
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        for index in 0..<count {
            let processID = processIDs[index]
            if processBundleID(processID) == bundleIdentifier { return processID }
        }
        return nil
    }

    private func processBundleID(_ objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var bundleID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &bundleID) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return bundleID?.takeUnretainedValue() as String?
    }

    /// `kAudioTapPropertyUID` returns a retained CF object according to the
    /// installed SDK, so ownership transfers exactly once here.
    private func uid(for objectID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let uid else {
            throw CoreAudioCaptureError.osStatus(status, "Could not read the process-tap identifier.")
        }
        return uid.takeRetainedValue() as String
    }
}

#else

public final class CoreAudioProcessTapCapture: CaptureResourceLifecycle {
    public let collector: PCMBufferCollector
    public let route: AudioRouteFacts
    public private(set) var format: AudioFormatFacts?
    public private(set) var generation: UInt64

    public init(
        route: AudioRouteFacts,
        collector: PCMBufferCollector,
        generation: UInt64 = 1,
        aggregateName: String = "Space Visualizer Music Tap",
        clock: AudioTimestampClock = SystemAudioTimestampClock()
    ) {
        self.route = route
        self.collector = collector
        self.generation = generation
    }

    public func start() throws { throw CoreAudioCaptureError.unsupportedPlatform }
    public func stop() {}
    public func destroy() {}
    public func invalidateForRouteChange() {
        generation &+= 1
        collector.reset(generation: generation)
    }
}

#endif
