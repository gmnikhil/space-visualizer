import Foundation
@testable import SpaceVisualizerCore

final class TestAudioTimestampClock: AudioTimestampClock {
    private let lock = NSLock()
    private var value: UInt64

    var now: UInt64 {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }

    init(now: UInt64 = 1_000_000_000) {
        self.value = now
    }

    func nowNanoseconds() -> UInt64 { now }
    func nanoseconds(for timestamp: UInt64) -> UInt64? { timestamp > 0 ? timestamp : nil }
    func timestamp(forNanoseconds nanoseconds: UInt64) -> UInt64? { nanoseconds }
    func ageNanoseconds(of timestamp: UInt64, nowNanoseconds: UInt64) -> UInt64? {
        guard let sample = nanoseconds(for: timestamp) else { return nil }
        return nowNanoseconds >= sample ? nowNanoseconds - sample : 0
    }
}

extension TrackSnapshot {
    static let fixtureTrack = TrackSnapshot(
        title: "Control Study",
        artist: "SpaceVisualizer Test Fixture",
        album: "Diagnostics",
        playbackState: .playing,
        position: 12,
        duration: 48,
        artworkAvailable: false
    )
}

extension AudioRouteFacts {
    static let fixtureSpeaker = AudioRouteFacts(
        id: "fixture-speaker",
        name: "Built-in Speakers",
        kind: .builtInSpeaker,
        isActive: true,
        sampleRate: 48_000,
        channelCount: 2
    )
}

extension AudioFormatFacts {
    static let fixtureStereo = AudioFormatFacts(
        sampleRate: 48_000,
        channelCount: 2,
        isInterleaved: true,
        sampleFormat: .float32
    )
}

extension AudioFeatures {
    static let fixtureLive = AudioFeatures(
        timestamp: 1,
        rms: 0.4,
        peak: 0.8,
        bass: 0.9,
        mids: 0.3,
        highs: 0.1,
        isSilent: false,
        isFresh: true,
        generation: 1
    )

    static let fixtureSilent = AudioFeatures(
        timestamp: 2,
        rms: 0,
        peak: 0,
        bass: 0,
        mids: 0,
        highs: 0,
        isSilent: true,
        isFresh: true,
        generation: 1
    )
}

extension RawMusicSnapshot {
    static let fixtureRaw = RawMusicSnapshot(
        title: "Control Study",
        artist: "SpaceVisualizer Test Fixture",
        album: "Diagnostics",
        playbackState: .playing,
        position: 12,
        duration: 48,
        artworkAvailable: false
    )
}

extension TestEvidence {
    static let fixtureControlFailure = TestEvidence(
        phase: .unprotectedControl,
        buildContext: "test",
        route: .fixtureSpeaker,
        format: .fixtureStereo,
        automationPermission: "authorized",
        systemAudioPermission: "authorized",
        metadataAvailable: true,
        playbackAudible: false,
        freshSamples: false,
        controlVerified: false,
        signalPresent: false,
        expectedBand: "bass",
        measuredBand: nil,
        rms: 0,
        events: ["control source unavailable"],
        result: .inconclusive
    )

    static let fixtureSubscriptionPass = TestEvidence(
        phase: .streamedSubscription,
        buildContext: "test",
        route: .fixtureSpeaker,
        format: .fixtureStereo,
        automationPermission: "authorized",
        systemAudioPermission: "authorized",
        metadataAvailable: true,
        playbackAudible: true,
        freshSamples: true,
        controlVerified: true,
        signalPresent: true,
        expectedBand: "mids",
        measuredBand: "mids",
        rms: 0.3,
        result: .pass
    )

    static let fixtureSubscriptionUnavailable = TestEvidence(
        phase: .streamedSubscription,
        buildContext: "test",
        route: .fixtureSpeaker,
        format: .fixtureStereo,
        automationPermission: "authorized",
        systemAudioPermission: "authorized",
        metadataAvailable: true,
        playbackAudible: true,
        freshSamples: false,
        controlVerified: true,
        signalPresent: false,
        events: ["Music reports playback; no samples arrived"],
        result: .inconclusive
    )
}

extension DiagnosticReport {
    static let fixture = DiagnosticReport(
        appBuild: "test",
        tests: [.fixtureSubscriptionPass]
    )
}
