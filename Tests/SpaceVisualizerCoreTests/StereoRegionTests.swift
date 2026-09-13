import Foundation
import XCTest
@testable import SpaceVisualizerCore

final class StereoRegionTests: XCTestCase {
    private func analyze(left: Double?, right: Double?, phase: Double = 1,
                         sampleRate: Double = 48_000) -> AudioFeatures {
        let size = AudioAnalyzerConfiguration.windowSize(sampleRate: sampleRate)
        let analyzer = AudioAnalyzer(configuration: AudioAnalyzerConfiguration(
            sampleRate: sampleRate, channelCount: 2, isInterleaved: true, fftSize: size))
        var samples: [Float] = []
        for index in 0..<size {
            func tone(_ frequency: Double?) -> Float {
                guard let frequency else { return 0 }
                return Float(0.04 * sin(2 * Double.pi * frequency * Double(index) / sampleRate))
            }
            samples.append(tone(left))
            samples.append(tone(right) * Float(phase))
        }
        return analyzer.analyze(samples: samples, timestamp: 1, generation: 1)
    }

    private func feature(level: Float, generation: UInt64 = 1) -> AudioFeatures {
        let levels = Array(repeating: level, count: StereoRegions.count)
        return AudioFeatures(timestamp: 1, rms: level, peak: level, bass: level, mids: level, highs: level,
                             stereoRegions: StereoRegionLevels(left: levels, right: levels),
                             isSilent: false, isFresh: true, generation: generation)
    }

    private func strongest(_ levels: [Float]) -> Int? {
        levels.indices.max { levels[$0] < levels[$1] }
    }

    func testLeftAndRightIsolationAcrossSampleRates() throws {
        for rate in [48_000.0, 96_000, 192_000] {
            let leftOnly = try XCTUnwrap(analyze(left: 1_200, right: nil, sampleRate: rate).stereoRegions)
            XCTAssertEqual(strongest(leftOnly.left), 7)
            XCTAssertTrue(leftOnly.right.allSatisfy { $0 == 0 })
            let rightOnly = try XCTUnwrap(analyze(left: nil, right: 7_000, sampleRate: rate).stereoRegions)
            XCTAssertEqual(strongest(rightOnly.right), 11)
            XCTAssertTrue(rightOnly.left.allSatisfy { $0 == 0 })
            let split = try XCTUnwrap(analyze(left: 1_200, right: 7_000, sampleRate: rate).stereoRegions)
            XCTAssertEqual(strongest(split.left), 7)
            XCTAssertEqual(strongest(split.right), 11)
        }
    }

    func testEveryRegionHasAnIndependentFrequencyTarget() throws {
        for region in 0..<StereoRegions.count {
            let frequency = (StereoRegions.edges[region] + StereoRegions.edges[region + 1]) / 2
            let stereo = try XCTUnwrap(analyze(left: frequency, right: nil).stereoRegions)
            XCTAssertEqual(strongest(stereo.left), region, "Region \(region), tone \(frequency) Hz")
            XCTAssertTrue(stereo.left.allSatisfy { $0.isFinite && (0...1).contains($0) })
        }
    }

    func testCenteredAndOppositePhaseSignalsRemainEqualAndLive() throws {
        for phase in [1.0, -1.0] {
            let result = analyze(left: 1_200, right: 1_200, phase: phase)
            XCTAssertFalse(result.isSilent)
            let stereo = try XCTUnwrap(result.stereoRegions)
            XCTAssertEqual(stereo.left, stereo.right)
            XCTAssertGreaterThan(stereo.left[7], 0.1)
        }
    }

    func testMonoAndUnknownMultichannelLayoutsUseSymmetricFallback() throws {
        for channels in [1, 4] {
            let analyzer = AudioAnalyzer(configuration: AudioAnalyzerConfiguration(
                sampleRate: 48_000, channelCount: channels, isInterleaved: true))
            var samples: [Float] = []
            for index in 0..<2_048 {
                let sample = Float(0.04 * sin(2 * Double.pi * 1_200 * Double(index) / 48_000))
                samples.append(contentsOf: Array(repeating: sample, count: channels))
            }
            let stereo = try XCTUnwrap(analyzer.analyze(samples: samples, timestamp: 1, generation: 1).stereoRegions)
            XCTAssertEqual(stereo.left, stereo.right)
            XCTAssertEqual(strongest(stereo.left), 7)
        }
    }

    func testInvalidAndSilentInputCannotCreateStereoMotion() {
        let analyzer = AudioAnalyzer(configuration: AudioAnalyzerConfiguration(
            sampleRate: 48_000, channelCount: 2, isInterleaved: true))
        for samples in [[], Array(repeating: Float.zero, count: 4_096),
                        Array(repeating: Float.nan, count: 4_096)] {
            let result = analyzer.analyze(samples: samples, timestamp: 1, generation: 1)
            XCTAssertTrue(result.isSilent)
            XCTAssertTrue(SpatialScene.balls(features: result, reduceMotion: false).allSatisfy { $0.energy == 0 })
        }
        let stale = analyzer.analyze(samples: Array(repeating: 0.1, count: 4_096),
                                     timestamp: 1, generation: 1, isFresh: false)
        XCTAssertNil(stale.stereoRegions)
        XCTAssertFalse(stale.isFresh)
    }

    func testLegacyDecodingAndStereoRoundTrip() throws {
        let value = feature(level: 0.5)
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        XCTAssertEqual(try JSONDecoder().decode(AudioFeatures.self, from: data), value)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "stereoRegions")
        let legacy = try JSONDecoder().decode(AudioFeatures.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.stereoRegions)
    }

    func testSmoothingUsesElapsedTimeAndMatchesPartners() throws {
        let interval = AudioTiming.smoothingReferenceIntervalNanoseconds
        var oneStep = FeatureSmoother()
        var twoSteps = FeatureSmoother()
        let target = feature(level: 0.8)
        let one = try XCTUnwrap(oneStep.ingest(target, elapsedNanoseconds: interval * 2).stereoRegions)
        _ = twoSteps.ingest(target, elapsedNanoseconds: interval)
        let two = try XCTUnwrap(twoSteps.ingest(target, elapsedNanoseconds: interval).stereoRegions)
        XCTAssertEqual(one.left, one.right)
        for region in 0..<StereoRegions.count {
            XCTAssertEqual(one.left[region], two.left[region], accuracy: 0.00001)
        }
        // Saturate all regions before comparing their release speeds.
        _ = oneStep.ingest(feature(level: 1), elapsedNanoseconds: interval * 100)
        let released = try XCTUnwrap(oneStep.ingest(feature(level: 0), elapsedNanoseconds: interval).stereoRegions)
        XCTAssertGreaterThan(released.left[0], released.left[4])
        XCTAssertGreaterThan(released.left[4], released.left[10])
        XCTAssertEqual(released.left, released.right)
    }

    func testSmoothingResetsForStaleGenerationAndExplicitReset() throws {
        var smoother = FeatureSmoother()
        _ = smoother.ingest(feature(level: 1))
        XCTAssertNil(smoother.ingest(.settled).stereoRegions)
        let fresh = try XCTUnwrap(smoother.ingest(feature(level: 0)).stereoRegions)
        XCTAssertTrue(fresh.left.allSatisfy { $0 == 0 })
        _ = smoother.ingest(feature(level: 1))
        let changed = try XCTUnwrap(smoother.ingest(feature(level: 0, generation: 2)).stereoRegions)
        XCTAssertTrue(changed.left.allSatisfy { $0 == 0 })
        _ = smoother.ingest(feature(level: 1, generation: 2))
        smoother.reset()
        XCTAssertNil(smoother.current.stereoRegions)
    }

    func testFixedMirroredPairsAndChannelSpecificHeight() {
        let quiet = SpatialScene.balls(features: .settled, reduceMotion: false)
        var input = feature(level: 0)
        input.stereoRegions?.left[7] = 0.8
        let balls = SpatialScene.balls(features: input, reduceMotion: false)
        XCTAssertEqual(balls.count, 28)
        XCTAssertEqual(balls.map(\.x), quiet.map(\.x))
        XCTAssertEqual(balls.filter { $0.energy > 0 }.count, 1)
        XCTAssertTrue(balls.first { $0.energy > 0 }!.x < 0)
        input.stereoRegions?.left[7] = 0
        input.stereoRegions?.right[7] = 0.8
        let rightOnly = SpatialScene.balls(features: input, reduceMotion: false)
        XCTAssertEqual(rightOnly.filter { $0.energy > 0 }.count, 1)
        XCTAssertTrue(rightOnly.first { $0.energy > 0 }!.x > 0)
        input.stereoRegions?.left[7] = 0.8
        let centered = SpatialScene.balls(features: input, reduceMotion: false)
        for index in stride(from: 0, to: centered.count, by: 2) {
            XCTAssertEqual(centered[index].y, centered[index + 1].y)
            XCTAssertEqual(centered[index].radius, centered[index + 1].radius)
        }
        for index in stride(from: 0, to: balls.count, by: 2) {
            let left = balls[index]
            let right = balls[index + 1]
            XCTAssertEqual(left.x, -right.x, accuracy: 0.000001)
            XCTAssertEqual(left.depth, right.depth)
            XCTAssertEqual(left.palette, right.palette)
            XCTAssertEqual(left.floorY, right.floorY)
            XCTAssertEqual(right.y, quiet[index + 1].y)
            XCTAssertLessThan(right.y, right.floorY)
        }
        XCTAssertEqual(balls.filter { $0.palette == 0 }.count, 8)
        XCTAssertEqual(balls.filter { $0.palette == 1 }.count, 12)
        XCTAssertEqual(balls.filter { $0.palette == 2 }.count, 8)
        XCTAssertEqual(SpatialScene.balls(features: input, reduceMotion: true), quiet)
        input.isSilent = true
        XCTAssertEqual(SpatialScene.balls(features: input, reduceMotion: false), quiet)
        input.isSilent = false
        input.isFresh = false
        XCTAssertEqual(SpatialScene.balls(features: input, reduceMotion: false), quiet)
    }

    func testMalformedRegionValuesAreBounded() {
        var input = feature(level: 0)
        input.stereoRegions = StereoRegionLevels(left: [.nan, .infinity, -1, 5], right: [])
        let balls = SpatialScene.balls(features: input, reduceMotion: false)
        XCTAssertTrue(balls.allSatisfy { $0.energy.isFinite && (0...1).contains($0.energy) })
        XCTAssertEqual(balls.filter { $0.energy > 0 }.count, 1)
    }
}
