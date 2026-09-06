import XCTest

final class ConfigurationContractTests: XCTestCase {
    func testSpikeDoesNotDeclareMicrophoneOrScreenCaptureUsage() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoURL = root.appendingPathComponent("ResonantApp/Info.plist")
        let entitlementsURL = root.appendingPathComponent("ResonantApp/Resonant.entitlements")
        let info = try String(contentsOf: infoURL, encoding: .utf8)
        let entitlements = try String(contentsOf: entitlementsURL, encoding: .utf8)

        XCTAssertTrue(info.contains("NSAppleEventsUsageDescription"))
        XCTAssertTrue(info.contains("NSAudioCaptureUsageDescription"))
        XCTAssertFalse(info.contains("NSMicrophoneUsageDescription"))
        XCTAssertFalse(info.contains("NSScreenCaptureUsageDescription"))
        XCTAssertFalse(entitlements.contains("com.apple.security.device.audio-input"))
    }
}
