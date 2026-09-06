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
import AudioToolbox
import CoreAudio

/// A local process-tap resource. It feeds a bounded collector and never writes
/// PCM to disk. The caller owns the session and must stop/destroy it.
public final class CoreAudioProcessTapCapture: CaptureResourceLifecycle {
    public let collector: PCMBufferCollector
    public let route: AudioRouteFacts
    public private(set) var format: AudioFormatFacts?
    public private(set) var generation: UInt64 = 1

    public let telemetry = CaptureTelemetry()

    private let aggregateName: String
    private let tapPolicy: ProcessTapPolicy
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var directInput: DirectTapInput?
    private var audioUnit: AudioUnit?
    private var scratchStorage: UnsafeMutablePointer<Float>?
    private var scratchList: UnsafeMutablePointer<AudioBufferList>?
    private var scratchCapacityFrames = 4_096
    private var scratchChannelCount = 2
    private var isDestroyed = false
    private var isStarted = false

    public init(route: AudioRouteFacts, collector: PCMBufferCollector, aggregateName: String = "Resonant Diagnostic Tap") {
        self.route = route
        self.collector = collector
        self.aggregateName = aggregateName
        self.tapPolicy = .music(routeID: route.id)
    }

    deinit { destroy() }

    public func start() throws {
        guard !isDestroyed else { throw CoreAudioCaptureError.osStatus(-1, "Capture resource was already destroyed.") }
        guard !isStarted else { return }
        do {
            try createTapAndAggregate()
            let input = try DirectTapInput(device: aggregateID, tap: tapID,
                                           collector: collector, telemetry: telemetry)
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
        guard isStarted else { return }
        if let audioUnit {
            _ = AudioOutputUnitStop(audioUnit)
        }
        isStarted = false
    }

    public func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true
        stop()
        if let audioUnit {
            _ = AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
            self.audioUnit = nil
        }
        releaseScratch()
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
        collector.reset(generation: generation &+ 1)
    }

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
        var status = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard status == noErr else {
            throw CoreAudioCaptureError.osStatus(status, "Could not create the Music process tap. Check system-audio permission.")
        }
        tapID = newTapID

        let tapUID = try uid(for: tapID)
        let uid = "com.resonant.aggregate.\(UUID().uuidString)"
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: aggregateName,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: true
        ]

        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregateID)
        guard status == noErr else {
            throw CoreAudioCaptureError.osStatus(status, "Could not create the temporary aggregate audio device.")
        }
        aggregateID = newAggregateID
        try attachTap(tapUID, to: newAggregateID)
    }

    private func attachTap(_ tapUID: String, to aggregateID: AudioObjectID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(aggregateID, &address, 0, nil, &propertySize)
        guard status == noErr else {
            throw CoreAudioCaptureError.osStatus(status, "Could not inspect the aggregate device tap list.")
        }

        var list: CFArray? = nil
        status = withUnsafeMutablePointer(to: &list) { pointer in
            AudioObjectGetPropertyData(aggregateID, &address, 0, nil, &propertySize, pointer)
        }
        guard status == noErr else {
            throw CoreAudioCaptureError.osStatus(status, "Could not read the aggregate device tap list.")
        }

        var tapUIDs = (list as? [CFString]) ?? []
        let tapString = tapUID as CFString
        if !tapUIDs.contains(tapString) {
            tapUIDs.append(tapString)
            propertySize += UInt32(MemoryLayout<CFString>.stride)
        }
        list = tapUIDs as CFArray
        status = withUnsafeMutablePointer(to: &list) { pointer in
            AudioObjectSetPropertyData(aggregateID, &address, 0, nil, propertySize, pointer)
        }
        guard status == noErr else {
            throw CoreAudioCaptureError.osStatus(status, "Could not attach the Music tap to the aggregate device.")
        }
    }

    private func createInputUnit() throws {
        var componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &componentDescription) else {
            throw CoreAudioCaptureError.osStatus(-1, "The HAL output audio unit is unavailable.")
        }

        var unit: AudioUnit?
        var status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let unit else {
            throw CoreAudioCaptureError.osStatus(status, "Could not create the HAL output audio unit.")
        }
        audioUnit = unit

        var enableInput: UInt32 = 1
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        try check(status, "Could not enable audio-unit input.")

        var disableOutput: UInt32 = 0
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,
            &disableOutput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        try check(status, "Could not disable the audio-unit output.")

        var device = aggregateID
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        try check(status, "Could not attach the aggregate device to the audio unit.")

        var callback = AURenderCallbackStruct(
            inputProc: Self.renderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callback,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        try check(status, "Could not install the audio capture callback.")

        // Match the single interleaved Float32 buffer used by render().
        let nativeFormat = try readStreamFormat(from: unit)
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: nativeFormat.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: nativeFormat.mChannelsPerFrame * 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: nativeFormat.mChannelsPerFrame * 4,
            mChannelsPerFrame: nativeFormat.mChannelsPerFrame,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output, 1, &clientFormat,
                                      UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        try check(status, "Could not configure interleaved Float32 capture.")
        status = AudioUnitInitialize(unit)
        try check(status, "Could not initialize the audio capture unit.")

        do {
            let streamFormat = try readStreamFormat(from: unit)
            scratchChannelCount = max(1, Int(streamFormat.mChannelsPerFrame))
            format = AudioFormatFacts(
                sampleRate: streamFormat.mSampleRate,
                channelCount: scratchChannelCount,
                isInterleaved: (streamFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0,
                sampleFormat: streamFormat.mBitsPerChannel == 32 ? .float32 : .unknown
            )
        } catch {
            _ = AudioUnitUninitialize(unit)
            throw error
        }

        allocateScratch()
        status = AudioOutputUnitStart(unit)
        try check(status, "Could not start the audio capture unit. macOS may still be waiting for permission.")
    }

    private func readStreamFormat(from unit: AudioUnit) throws -> AudioStreamBasicDescription {
        var streamFormat = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &streamFormat,
            &size
        )
        guard status == noErr, streamFormat.mSampleRate > 0, streamFormat.mChannelsPerFrame > 0 else {
            throw CoreAudioCaptureError.invalidFormat("The aggregate device returned no usable PCM format.")
        }
        return streamFormat
    }

    private func allocateScratch() {
        releaseScratch()
        scratchStorage = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacityFrames * scratchChannelCount)
        scratchList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        scratchList?.pointee = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: UInt32(scratchChannelCount),
                mDataByteSize: UInt32(scratchCapacityFrames * scratchChannelCount * MemoryLayout<Float>.size),
                mData: scratchStorage
            )
        )
    }

    private func releaseScratch() {
        scratchList?.deallocate()
        scratchList = nil
        scratchStorage?.deallocate()
        scratchStorage = nil
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

        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioObjectID>.alignment)
        defer { raw.deallocate() }
        let processIDs = raw.assumingMemoryBound(to: AudioObjectID.self)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, processIDs) == noErr else { return nil }

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

    private func uid(for objectID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let uid else {
            throw CoreAudioCaptureError.osStatus(status, "Could not read the process-tap identifier.")
        }
        return uid as String
    }

    private func check(_ status: OSStatus, _ message: String) throws {
        guard status == noErr else { throw CoreAudioCaptureError.osStatus(status, message) }
    }

    private func render(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        numberFrames: UInt32
    ) -> OSStatus {
        guard let audioUnit, let scratchList, let scratchStorage,
              numberFrames <= scratchCapacityFrames,
              let format else {
            telemetry.record(frames: 0, status: kAudio_ParamError)
            return kAudio_ParamError
        }
        scratchList.pointee.mBuffers.mDataByteSize = numberFrames * UInt32(format.channelCount) * UInt32(MemoryLayout<Float>.size)
        let status = AudioUnitRender(audioUnit, actionFlags, timeStamp, 1, numberFrames, scratchList)
        telemetry.record(frames: numberFrames, status: status)
        guard status == noErr else { return status }
        let count = Int(numberFrames) * format.channelCount
        let samples = UnsafeBufferPointer(start: scratchStorage, count: count)
        let hostTime = timeStamp.pointee.mHostTime
        _ = collector.accept(
            samples: samples,
            timestamp: hostTime,
            sampleRate: format.sampleRate,
            channelCount: format.channelCount,
            generation: generation
        )
        return noErr
    }

    private static let renderCallback: AURenderCallback = { refCon, actionFlags, timeStamp, _, numberFrames, _ in
        let capture = Unmanaged<CoreAudioProcessTapCapture>.fromOpaque(refCon).takeUnretainedValue()
        return capture.render(actionFlags: actionFlags, timeStamp: timeStamp, numberFrames: numberFrames)
    }
}

#else

public final class CoreAudioProcessTapCapture: CaptureResourceLifecycle {
    public let collector: PCMBufferCollector
    public let route: AudioRouteFacts
    public private(set) var format: AudioFormatFacts?
    public private(set) var generation: UInt64 = 1

    public init(route: AudioRouteFacts, collector: PCMBufferCollector, aggregateName: String = "Resonant Diagnostic Tap") {
        self.route = route
        self.collector = collector
    }

    public func start() throws { throw CoreAudioCaptureError.unsupportedPlatform }
    public func stop() {}
    public func destroy() {}
    public func invalidateForRouteChange() { generation &+= 1; collector.reset(generation: generation) }
}

#endif
