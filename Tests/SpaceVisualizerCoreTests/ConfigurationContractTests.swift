import XCTest

final class ConfigurationContractTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testBuildDeclaresOneSpaceVisualizerProductWithConsistentNames() throws {
        let package = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let buildScript = try String(contentsOf: root.appendingPathComponent("scripts/build-space-visualizer-app.sh"), encoding: .utf8)

        XCTAssertTrue(package.contains("name: \"SpaceVisualizer\""))
        XCTAssertTrue(package.contains("executable(name: \"SpaceVisualizer\", targets: [\"SpaceVisualizerApp\"]"))
        XCTAssertTrue(package.contains("name: \"SpaceVisualizerCore\""))
        XCTAssertTrue(package.contains("name: \"SpaceVisualizerApp\""))
        XCTAssertTrue(package.contains("name: \"SpaceVisualizerCoreTests\""))
        XCTAssertTrue(package.contains("name: \"SpaceVisualizerUITests\""))
        XCTAssertTrue(buildScript.contains(".build/Space Visualizer.app"))
        XCTAssertTrue(buildScript.contains(".build/Resonant.app"))
        XCTAssertTrue(buildScript.contains(".build/SpaceVisualizer.app"))
        XCTAssertFalse(package.contains("Resonant"))
    }

    func testProductionObservationUsesBoundedHelperRatherThanSynchronousUIPolling() throws {
        let metadata = try String(contentsOf: root.appendingPathComponent("Sources/SpaceVisualizerCore/MusicMetadata.swift"), encoding: .utf8)
        let adapter = try String(contentsOf: root.appendingPathComponent("Sources/SpaceVisualizerCore/MusicPlaybackQuery.swift"), encoding: .utf8)
        let contentView = try String(contentsOf: root.appendingPathComponent("Sources/SpaceVisualizerApp/ContentView.swift"), encoding: .utf8)

        XCTAssertFalse(metadata.contains("NSAppleScript"))
        XCTAssertFalse(contentView.contains(".task(id: engine.isMetadataObservationEnabled)"))
        XCTAssertTrue(adapter.contains("/usr/bin/osascript"))
        XCTAssertTrue(adapter.contains("MusicApplicationPresenceChecker"))
        XCTAssertTrue(adapter.contains("timeout: Self.timeout"))
    }

    func testDefaultShellPrioritizesCanvasAndKeepsDiagnosticsOptional() throws {
        let contentView = try String(contentsOf: root.appendingPathComponent("Sources/SpaceVisualizerApp/ContentView.swift"), encoding: .utf8)
        let refreshDriver = try String(contentsOf: root.appendingPathComponent("Sources/SpaceVisualizerApp/DisplayRefreshDriver.swift"), encoding: .utf8)

        XCTAssertTrue(contentView.contains("SpatialCanvasView"))
        XCTAssertTrue(contentView.contains("DiagnosticsPanel"))
        XCTAssertTrue(contentView.contains("Export audio-free report"))
        XCTAssertTrue(contentView.contains("Label(\"Export image\""))
        XCTAssertTrue(contentView.contains("ImageRenderer"))
        XCTAssertTrue(contentView.contains("3_840"))
        XCTAssertTrue(contentView.contains("trackDetails"))
        XCTAssertTrue(contentView.contains("formattedTime"))
        XCTAssertTrue(contentView.contains("track.album"))
        XCTAssertTrue(contentView.contains("track.position"))
        XCTAssertTrue(contentView.contains("TimelineView"))
        XCTAssertTrue(contentView.contains("from: playbackSecondAnchor(playback), by: 1"))
        XCTAssertTrue(contentView.contains("positionObservedAt"))
        XCTAssertTrue(contentView.contains("VisualizerExportView"))
        XCTAssertTrue(contentView.contains("songDetails(for: track, playback: playback)"))
        XCTAssertFalse(contentView.contains("toggleFullScreen"))
        XCTAssertFalse(contentView.contains("Start capture"))
        XCTAssertFalse(contentView.contains("TEST PHASE"))
        XCTAssertFalse(contentView.contains("Record current attempt"))
        XCTAssertFalse(contentView.contains(".task(id:"))
        XCTAssertTrue(refreshDriver.contains("preferred: requested"))
        XCTAssertTrue(refreshDriver.contains("viewDidMoveToWindow"))
        XCTAssertTrue(refreshDriver.contains("stopLink()"))
    }

    func testWindowLifecycleUsesVisibilitySleepHooksAndStaticReducedMotion() throws {
        let contentView = try String(contentsOf: root.appendingPathComponent("Sources/SpaceVisualizerApp/ContentView.swift"), encoding: .utf8)
        let observer = try String(contentsOf: root.appendingPathComponent("Sources/SpaceVisualizerApp/WindowVisibilityObserver.swift"), encoding: .utf8)
        let app = try String(contentsOf: root.appendingPathComponent("Sources/SpaceVisualizerApp/SpaceVisualizerApp.swift"), encoding: .utf8)

        XCTAssertTrue(app.contains("Window(\"Space Visualizer\", id: \"main\")"))
        XCTAssertTrue(contentView.contains("active: canvasIsActive && !reduceMotion"))
        XCTAssertTrue(contentView.contains("private let spatialScale: CGFloat = 0.75"))
        XCTAssertTrue(contentView.contains("scaleEffect(spatialScale, anchor: .center)"))
        XCTAssertTrue(contentView.contains("size.height * 0.50"))
        XCTAssertTrue(contentView.contains("min(size.width, size.height) * 0.28"))
        XCTAssertTrue(contentView.contains("accessibilityHint"))
        XCTAssertTrue(contentView.contains("NSWorkspace.willSleepNotification"))
        XCTAssertTrue(contentView.contains("NSWorkspace.didWakeNotification"))
        XCTAssertTrue(contentView.contains("NSApplication.willTerminateNotification"))
        XCTAssertTrue(observer.contains("didMiniaturizeNotification"))
        XCTAssertTrue(observer.contains("didChangeOcclusionStateNotification"))
        XCTAssertTrue(observer.contains("willCloseNotification"))
        XCTAssertTrue(observer.contains("forceHidden: name == NSWindow.willCloseNotification"))
        XCTAssertTrue(observer.contains("NSApplication.didHideNotification"))
        XCTAssertTrue(observer.contains("NSApplication.didUnhideNotification"))
        XCTAssertFalse(observer.contains("didResignKeyNotification"))
        XCTAssertFalse(observer.contains("didBecomeKeyNotification"))
    }

    func testCaptureUsesOnlyDirectMusicTapWithoutLegacyOrSystemFallback() throws {
        let capture = try String(contentsOf: root.appendingPathComponent("Sources/SpaceVisualizerCore/CoreAudioProcessTap.swift"), encoding: .utf8)
        let directInput = try String(contentsOf: root.appendingPathComponent("Sources/SpaceVisualizerCore/DirectTapInput.swift"), encoding: .utf8)
        let factory = try String(contentsOf: root.appendingPathComponent("Sources/SpaceVisualizerCore/DirectTapVisualizerSession.swift"), encoding: .utf8)

        XCTAssertTrue(directInput.contains("AudioDeviceCreateIOProcID"))
        XCTAssertTrue(capture.contains("kAudioAggregateDeviceTapListKey"))
        XCTAssertTrue(capture.contains("tapPolicy = .music"))
        XCTAssertFalse(capture.contains("AudioUnit"))
        XCTAssertFalse(capture.contains("AudioUnitRender"))
        XCTAssertTrue(factory.contains("DirectTapVisualizerSessionFactory"))
        XCTAssertFalse(factory.contains("all-system"))
    }

    func testBundleUsesProductionIdentityAndRequiredPurposeStrings() throws {
        let infoURL = root.appendingPathComponent("SpaceVisualizerApp/Info.plist")
        let entitlementsURL = root.appendingPathComponent("SpaceVisualizerApp/SpaceVisualizer.entitlements")
        let info = try String(contentsOf: infoURL, encoding: .utf8)
        let entitlements = try String(contentsOf: entitlementsURL, encoding: .utf8)

        XCTAssertTrue(info.contains("<string>Space Visualizer</string>"))
        XCTAssertTrue(info.contains("<string>SpaceVisualizer</string>"))
        XCTAssertTrue(info.contains("<string>com.spacevisualizer.app</string>"))
        XCTAssertTrue(info.contains("NSAppleEventsUsageDescription"))
        XCTAssertTrue(info.contains("NSAudioCaptureUsageDescription"))
        XCTAssertFalse(info.contains("NSMicrophoneUsageDescription"))
        XCTAssertFalse(info.contains("NSScreenCaptureUsageDescription"))
        XCTAssertFalse(entitlements.contains("com.apple.security.device.audio-input"))
        XCTAssertFalse(entitlements.contains("com.apple.security.network.client"))
        XCTAssertFalse(entitlements.contains("screen-capture"))
    }
}
