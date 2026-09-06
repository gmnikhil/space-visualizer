import XCTest
@testable import ResonantCore

final class VisualMappingTests: XCTestCase {
    func testBassMidsAndHighsMapToSeparateVisualDimensions() {
        let parameters = VisualParameters(features: AudioFeatures(
            timestamp: 1,
            rms: 0.4,
            peak: 0.8,
            bass: 0.8,
            mids: 0.5,
            highs: 0.2,
            isSilent: false,
            isFresh: true,
            generation: 1
        ))

        XCTAssertEqual(parameters.expansion, 0.8, accuracy: 0.0001)
        XCTAssertEqual(parameters.deformation, 0.5, accuracy: 0.0001)
        XCTAssertEqual(parameters.edgeDetail, 0.2, accuracy: 0.0001)
    }

    func testInvalidAndSilentFeaturesSettleBothVisualDimensions() {
        let silent = VisualParameters(features: .fixtureSilent)
        let stale = VisualParameters(features: AudioFeatures(
            timestamp: 1,
            rms: 1,
            peak: 1,
            bass: 1,
            mids: 1,
            highs: 1,
            isSilent: false,
            isFresh: false,
            generation: 1
        ))

        XCTAssertEqual(silent, .settled)
        XCTAssertEqual(stale, .settled)
    }

    func testVisualMappingClampsNonFiniteAndOutOfRangeValues() {
        let parameters = VisualParameters(features: AudioFeatures(
            timestamp: 1,
            rms: 1,
            peak: 1,
            bass: 3,
            mids: -0.5,
            highs: .infinity,
            isSilent: false,
            isFresh: true,
            generation: 1
        ))

        XCTAssertEqual(parameters.expansion, 1)
        XCTAssertEqual(parameters.deformation, 0)
        XCTAssertEqual(parameters.edgeDetail, 0)
    }
}
