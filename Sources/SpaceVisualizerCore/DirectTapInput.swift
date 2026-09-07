#if os(macOS)
import CoreAudio
import AudioToolbox

/// Reads only the private tap-only aggregate. Never writes to an output buffer.
final class DirectTapInput {
    private let device: AudioObjectID
    private let collector: PCMBufferCollector
    private let telemetry: CaptureTelemetry
    private let generation: UInt64
    private let clock: AudioTimestampClock
    private var procID: AudioDeviceIOProcID?
    private var started = false
    let format: AudioFormatFacts

    init(device: AudioObjectID, tap: AudioObjectID, collector: PCMBufferCollector,
         telemetry: CaptureTelemetry, generation: UInt64,
         clock: AudioTimestampClock = SystemAudioTimestampClock()) throws {
        self.device = device
        self.collector = collector
        self.telemetry = telemetry
        self.generation = generation
        self.clock = clock
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd)
        guard status == noErr else {
            throw CoreAudioCaptureError.osStatus(status, "Could not read tap PCM format.")
        }
        guard asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
              asbd.mBitsPerChannel == 32,
              asbd.mChannelsPerFrame > 0,
              asbd.mBytesPerFrame == asbd.mChannelsPerFrame * 4,
              asbd.mSampleRate.isFinite, asbd.mSampleRate > 0 else {
            throw CoreAudioCaptureError.invalidFormat("Direct tap requires packed interleaved Float32 PCM; unsupported formats are not reinterpreted.")
        }
        format = AudioFormatFacts(sampleRate: asbd.mSampleRate,
            channelCount: Int(asbd.mChannelsPerFrame), isInterleaved: true, sampleFormat: .float32)
    }

    func start() throws {
        var status = AudioDeviceCreateIOProcID(device, Self.callback,
            Unmanaged.passUnretained(self).toOpaque(), &procID)
        guard status == noErr, let procID else {
            throw CoreAudioCaptureError.osStatus(status, "Could not register direct tap input callback.")
        }
        status = AudioDeviceStart(device, procID)
        guard status == noErr else {
            stop()
            throw CoreAudioCaptureError.osStatus(status, "Could not start direct tap input.")
        }
        started = true
    }

    func stop() {
        guard let procID else { return }
        if started { _ = AudioDeviceStop(device, procID) }
        _ = AudioDeviceDestroyIOProcID(device, procID)
        self.procID = nil
        started = false
    }

    deinit { stop() }

    private func receive(_ input: UnsafePointer<AudioBufferList>, timestamp: UInt64) {
        let callbackAge = clock.ageNanoseconds(
            of: timestamp,
            nowNanoseconds: clock.nowNanoseconds()
        )
        // One tap, no physical input subdevices: reject unexpected layouts.
        guard input.pointee.mNumberBuffers == 1 else {
            telemetry.record(frames: 0, status: kAudio_ParamError,
                             callbackAgeNanoseconds: callbackAge)
            return
        }
        let buffer = input.pointee.mBuffers
        guard let data = buffer.mData, buffer.mNumberChannels == UInt32(format.channelCount),
              buffer.mDataByteSize > 0,
              buffer.mDataByteSize <= UInt32(format.channelCount * 4 * 4096),
              buffer.mDataByteSize % UInt32(format.channelCount * 4) == 0 else {
            telemetry.record(frames: 0, status: kAudio_ParamError,
                             callbackAgeNanoseconds: callbackAge)
            return
        }
        let count = Int(buffer.mDataByteSize) / 4
        let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count)
        _ = collector.accept(samples: samples, timestamp: timestamp,
            sampleRate: format.sampleRate, channelCount: format.channelCount, generation: generation)
        telemetry.record(
            frames: UInt32(count / format.channelCount),
            status: 0,
            callbackAgeNanoseconds: callbackAge
        )
    }

    private static let callback: AudioDeviceIOProc = { _, _, input, inputTime, _, _, context in
        guard let context else { return noErr }
        let owner = Unmanaged<DirectTapInput>.fromOpaque(context).takeUnretainedValue()
        owner.receive(input, timestamp: inputTime.pointee.mHostTime)
        return noErr
    }
}
#endif
