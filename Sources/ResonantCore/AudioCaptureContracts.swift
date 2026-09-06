import Foundation

public enum AudioPermissionStatus: String, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

public protocol AudioPermissionProviding: AnyObject {
    var status: AudioPermissionStatus { get }
    func requestPermission() -> AudioPermissionStatus
}

public final class AudioPermissionCoordinator {
    private let provider: AudioPermissionProviding
    public private(set) var status: AudioPermissionStatus
    public let requestsMicrophone = false

    public init(provider: AudioPermissionProviding) {
        self.provider = provider
        self.status = provider.status
    }

    @discardableResult
    public func ensurePermission() -> AudioPermissionStatus {
        if provider.status == .authorized {
            status = .authorized
            return status
        }
        status = provider.requestPermission()
        return status
    }

    public func updateStatus(_ status: AudioPermissionStatus) {
        self.status = status
    }

    public var recoveryAction: String {
        switch status {
        case .denied:
            return "Open System Settings → Privacy & Security → Screen & System Audio Recording, then retry."
        case .unavailable:
            return "System-audio capture is unavailable on this Mac or route."
        case .notDetermined:
            return "Start a capture test to let macOS ask for system-audio access."
        case .authorized:
            return "System-audio access is ready."
        }
    }
}

public protocol AudioRouteProviding {
    func availableRoutes() throws -> [AudioRouteFacts]
}

public enum AudioRouteResolution: Equatable, Sendable {
    case selected(AudioRouteFacts)
    case ambiguous([String])
    case unavailable(String)
}

public final class AudioRouteResolver {
    private let provider: AudioRouteProviding

    public init(provider: AudioRouteProviding) {
        self.provider = provider
    }

    public func routes() -> [AudioRouteFacts] {
        (try? provider.availableRoutes()) ?? []
    }

    public func resolve(preferredID: String?) -> AudioRouteResolution {
        let routes = self.routes()
        guard !routes.isEmpty else {
            return .unavailable("No audio output routes are available.")
        }
        if let preferredID {
            guard let route = routes.first(where: { $0.id == preferredID }) else {
                return .unavailable("The selected audio route is unavailable.")
            }
            return .selected(route)
        }
        if routes.count == 1, let route = routes.first {
            return .selected(route)
        }
        return .ambiguous(routes.map(\.name))
    }
}

/// Owns a temporary capture resource and guarantees stop/destroy happen once.
public final class CaptureSession {
    private let resource: CaptureResourceLifecycle
    private var didCleanUp = false

    public private(set) var isRunning = false

    public init(resource: CaptureResourceLifecycle) {
        self.resource = resource
    }

    public func start() throws {
        guard !isRunning, !didCleanUp else { return }
        do {
            try resource.start()
            isRunning = true
        } catch {
            cleanup()
            throw error
        }
    }

    public func stop() {
        cleanup()
    }

    private func cleanup() {
        guard !didCleanUp else { return }
        didCleanUp = true
        resource.stop()
        resource.destroy()
        isRunning = false
    }

    deinit { cleanup() }
}

public final class StreamGenerationController {
    public private(set) var current: UInt64 = 1
    public private(set) var didInvalidateSamples = false

    public init() {}

    public func routeChanged() {
        current &+= 1
        didInvalidateSamples = true
    }

    public func formatChanged() {
        current &+= 1
        didInvalidateSamples = true
    }

    public func accepts(_ generation: UInt64) -> Bool {
        generation == current
    }
}

#if os(macOS)
import CoreAudio

public final class SystemAudioPermissionProvider: AudioPermissionProviding {
    public private(set) var status: AudioPermissionStatus = .notDetermined

    public init() {}

    /// Core Audio presents the system prompt when a process tap is started.
    /// This method intentionally does not use a microphone or screen-capture preflight.
    public func requestPermission() -> AudioPermissionStatus {
        status
    }

    public func markAuthorized() { status = .authorized }
    public func markDenied() { status = .denied }
}

public final class CoreAudioRouteProvider: AudioRouteProviding {
    public init() {}

    public func availableRoutes() throws -> [AudioRouteFacts] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard status == noErr else { throw CoreAudioCaptureError.osStatus(status, "Could not enumerate audio devices.") }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &ids
        )
        guard status == noErr else { throw CoreAudioCaptureError.osStatus(status, "Could not read audio devices.") }

        return ids.compactMap { id in
            guard let name = Self.stringProperty(id: id, selector: kAudioObjectPropertyName),
                  let uid = Self.stringProperty(id: id, selector: kAudioDevicePropertyDeviceUID) else { return nil }
            let hasOutput = Self.hasOutput(id: id)
            guard hasOutput else { return nil }
            let transport = Self.transportType(id: id)
            let kind: AudioRouteKind
            if transport == kAudioDeviceTransportTypeAirPlay {
                kind = .airPlay
            } else if transport == kAudioDeviceTransportTypeBuiltIn {
                kind = .builtInSpeaker
            } else {
                kind = .other
            }
            let active = Self.isDefaultOutput(id: id)
            return AudioRouteFacts(
                id: uid,
                name: name,
                kind: kind,
                isActive: active,
                sampleRate: Self.nominalSampleRate(id: id),
                channelCount: Self.outputChannelCount(id: id)
            )
        }
    }

    private static func stringProperty(id: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value?.takeUnretainedValue() as String?
    }

    private static func hasOutput(id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let listPointer = raw.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, listPointer) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(listPointer)
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func nominalSampleRate(id: AudioObjectID) -> Double? {
        scalarProperty(id: id, selector: kAudioDevicePropertyNominalSampleRate)
    }

    private static func transportType(id: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    private static func outputChannelCount(id: AudioObjectID) -> Int? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let listPointer = raw.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, listPointer) == noErr else { return nil }
        return UnsafeMutableAudioBufferListPointer(listPointer).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func scalarProperty(id: AudioObjectID, selector: AudioObjectPropertySelector) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = 0.0
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func isDefaultOutput(id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &value) == noErr else { return false }
        return value == id
    }
}
#else

public final class SystemAudioPermissionProvider: AudioPermissionProviding {
    public let status: AudioPermissionStatus = .unavailable
    public init() {}
    public func requestPermission() -> AudioPermissionStatus { status }
}

public final class CoreAudioRouteProvider: AudioRouteProviding {
    public init() {}
    public func availableRoutes() throws -> [AudioRouteFacts] { throw MusicBridgeError.unsupportedPlatform }
}

#endif
