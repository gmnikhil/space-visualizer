import XCTest
@testable import ResonantCore

final class DiagnosticViewModelContractTests: XCTestCase {
    func testViewModelStartsWithAnExplicitFeasibilityPreviewState() {
        let model = DiagnosticViewModel.preview

        XCTAssertEqual(model.title, "Resonant feasibility preview")
        XCTAssertTrue(model.isPreview)
        XCTAssertEqual(model.audioLabel, "Not connected")
        XCTAssertEqual(model.metadataLabel, "Track details unknown")
        XCTAssertEqual(model.previewLabel, "FEASIBILITY PREVIEW · NOT PRODUCTION RENDERER")
        XCTAssertTrue(model.canStartCapture)
        XCTAssertFalse(model.canStopCapture)
        XCTAssertEqual(model.liveLabel, "NOT LIVE · NO AUDIO-DRIVEN MOTION")
    }

    func testMetadataPermissionPresentationIsExplicitAndRecoverable() {
        let model = DiagnosticViewModel.preview
        model.apply(.metadataPermissionRequired)

        XCTAssertTrue(model.showsMetadataRecovery)
        XCTAssertTrue(model.metadataPermissionExplanation.contains("metadata"))
        XCTAssertTrue(model.metadataRecoveryLabel.contains("System Settings"))
        XCTAssertEqual(model.metadataTitleLabel, "Unknown title")
        XCTAssertEqual(model.metadataArtistLabel, "Unknown artist")
        XCTAssertEqual(model.metadataAlbumLabel, "Unknown album")
        XCTAssertEqual(model.metadataPlaybackStateLabel, "Unknown state")
        XCTAssertEqual(model.metadataPositionLabel, "Unknown position")
        XCTAssertEqual(model.metadataDurationLabel, "Unknown duration")
    }

    func testViewModelKeepsAudioAndMetadataLabelsIndependent() {
        let model = DiagnosticViewModel.preview
        model.apply(.metadataUnavailable("Automation denied"))
        model.apply(.captureStarted(route: .fixtureSpeaker, format: .fixtureStereo))
        model.apply(.features(.fixtureLive))

        XCTAssertEqual(model.metadataLabel, "Track details unavailable")
        XCTAssertEqual(model.audioLabel, "Live signal")
        XCTAssertEqual(model.signalFreshnessLabel, "Fresh samples")
        XCTAssertEqual(model.routeLabel, "Built-in Speakers")
        XCTAssertEqual(model.formatLabel, "48000 Hz · 2 ch · float32")
        XCTAssertEqual(model.bandLabels, ["Bass 90%", "Mids 30%", "Highs 10%"])
        XCTAssertTrue(model.isLive)
        XCTAssertFalse(model.canStartCapture)
        XCTAssertTrue(model.canStopCapture)
        XCTAssertEqual(model.liveLabel, "LIVE · FRESH AUDIO")
    }

    func testDisplayModesExposeBothProofViews() {
        XCTAssertEqual(DiagnosticDisplayMode.allCases, [.combined, .twoD, .threeD])
        XCTAssertEqual(DiagnosticDisplayMode.combined.title, "2D + 3D")
        XCTAssertEqual(DiagnosticDisplayMode.twoD.title, "2D signal")
        XCTAssertEqual(DiagnosticDisplayMode.threeD.title, "3D shape")
    }

    func testCaptureControlsExposeSafeStartAndStopStates() {
        let model = DiagnosticViewModel.preview
        XCTAssertTrue(model.canStartCapture)
        XCTAssertFalse(model.canStopCapture)

        model.apply(.captureConnecting)
        XCTAssertFalse(model.canStartCapture)
        XCTAssertTrue(model.canStopCapture)

        model.apply(.captureStarted(route: .fixtureSpeaker, format: .fixtureStereo))
        XCTAssertFalse(model.canStartCapture)
        XCTAssertTrue(model.canStopCapture)

        model.apply(.stopped)
        XCTAssertTrue(model.canStartCapture)
        XCTAssertFalse(model.canStopCapture)
    }

    func testAllTestPhasesRemainExplicit() {
        XCTAssertEqual(TestPhase.allCases, [.unprotectedControl, .streamedSubscription, .downloadedSubscription])
        XCTAssertEqual(TestPhase.unprotectedControl.rawValue, "unprotected-control")
        XCTAssertEqual(TestPhase.streamedSubscription.rawValue, "streamed-subscription")
        XCTAssertEqual(TestPhase.downloadedSubscription.rawValue, "downloaded-subscription")
    }

    func testReducedMotionReducesDecorativeGeometryButKeepsTheAudioContract() {
        let livePolicy = VisualPreviewPolicy(features: .fixtureLive, reduceMotion: false)
        let reducedPolicy = VisualPreviewPolicy(features: .fixtureLive, reduceMotion: true)
        let silentPolicy = VisualPreviewPolicy(features: .fixtureSilent, reduceMotion: false)

        XCTAssertEqual(livePolicy.ringCount, 13)
        XCTAssertEqual(livePolicy.pointCount, 96)
        XCTAssertTrue(livePolicy.isFeatureDriven)
        XCTAssertEqual(reducedPolicy.ringCount, 7)
        XCTAssertEqual(reducedPolicy.pointCount, 48)
        XCTAssertTrue(reducedPolicy.reduceMotion)
        XCTAssertFalse(silentPolicy.isFeatureDriven)
    }

    func testViewModelDistinguishesAnActiveSessionFromReceivedAudio() {
        let model = DiagnosticViewModel.preview
        model.apply(.captureStarted(route: .fixtureSpeaker, format: .fixtureStereo))

        XCTAssertEqual(model.audioLabel, "Connecting")
        XCTAssertFalse(model.isLive)
        XCTAssertEqual(model.liveLabel, "NOT LIVE · NO AUDIO-DRIVEN MOTION")

        model.apply(.captureNoSamples)
        XCTAssertEqual(model.audioLabel, "Signal unavailable")
        XCTAssertFalse(model.isLive)
    }

    func testViewModelShowsSilentInsteadOfInventedMotion() {
        let model = DiagnosticViewModel.preview
        model.apply(.features(.fixtureSilent))

        XCTAssertEqual(model.audioLabel, "Silent")
        XCTAssertEqual(model.signalFreshnessLabel, "Fresh samples")
        XCTAssertFalse(model.isLive)
        XCTAssertEqual(model.visualParameters, .settled)
        XCTAssertEqual(model.liveLabel, "NOT LIVE · NO AUDIO-DRIVEN MOTION")
    }

    func testRecoveryStateIsExplicitAndDoesNotBecomeLive() {
        let model = DiagnosticViewModel.preview
        model.apply(.captureFailed("System-audio permission denied"))

        XCTAssertEqual(model.audioLabel, "Capture failed")
        XCTAssertFalse(model.isLive)
        XCTAssertEqual(model.visualParameters, .settled)
    }
}

private extension AudioRouteFacts {
    static let fixtureSpeaker = AudioRouteFacts(
        id: "fixture-speaker",
        name: "Built-in Speakers",
        kind: .builtInSpeaker,
        isActive: true,
        sampleRate: 48_000,
        channelCount: 2
    )
}

private extension AudioFormatFacts {
    static let fixtureStereo = AudioFormatFacts(
        sampleRate: 48_000,
        channelCount: 2,
        isInterleaved: true,
        sampleFormat: .float32
    )
}

private extension AudioFeatures {
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
