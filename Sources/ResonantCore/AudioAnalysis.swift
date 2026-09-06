import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

public struct AudioFrame: Equatable, Sendable {
    public var timestamp: UInt64
    public var sampleRate: Double
    public var channelCount: Int
    public var generation: UInt64
    public var samples: [Float]
    public var isFresh: Bool

    public init(
        timestamp: UInt64,
        sampleRate: Double,
        channelCount: Int,
        generation: UInt64,
        samples: [Float],
        isFresh: Bool
    ) {
        self.timestamp = timestamp
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.generation = generation
        self.samples = samples
        self.isFresh = isFresh
    }
}

/// A bounded sample queue. The capture adapter owns its input buffer; this
/// type deliberately drops the oldest samples when the analysis worker lags.
public final class AudioRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private var storage: [Float]
    private var readIndex = 0
    private var writeIndex = 0
    private var storedCount = 0
    private let lock = NSLock()

    public init(capacity: Int) {
        precondition(capacity > 0, "AudioRingBuffer capacity must be positive")
        self.capacity = capacity
        self.storage = Array(repeating: 0, count: capacity)
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCount
    }

    @discardableResult
    public func write(_ samples: [Float]) -> Int {
        samples.withUnsafeBufferPointer { write($0) }
    }

    @discardableResult
    public func write(_ samples: UnsafeBufferPointer<Float>) -> Int {
        guard !samples.isEmpty else { return 0 }
        // The producer is the real-time render callback. If the analysis
        // consumer owns the lock, drop this bounded block rather than making
        // the callback wait behind an unbounded mutex.
        guard lock.try() else { return samples.count }
        defer { lock.unlock() }
        var dropped = 0
        for sample in samples {
            if storedCount == capacity {
                readIndex = (readIndex + 1) % capacity
                storedCount -= 1
                dropped += 1
            }
            storage[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            storedCount += 1
        }
        return dropped
    }

    /// Consume the newest complete analysis window, not a queued history.
    /// Leave short input untouched so subsequent callbacks can complete it.
    public func readLatestWindow(sampleCount: Int, retainingSamples: Int = 0) -> [Float] {
        guard sampleCount > 0, retainingSamples >= 0, retainingSamples < sampleCount else { return [] }
        lock.lock()
        defer { lock.unlock() }
        guard storedCount >= sampleCount else { return [] }
        readIndex = (readIndex + storedCount - sampleCount) % capacity
        var result = [Float]()
        result.reserveCapacity(sampleCount)
        for _ in 0..<sampleCount {
            result.append(storage[readIndex])
            readIndex = (readIndex + 1) % capacity
        }
        readIndex = (readIndex - retainingSamples + capacity) % capacity
        storedCount = retainingSamples
        return result
    }

    public func read(maximumSamples: Int) -> [Float] {
        guard maximumSamples > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let amount = min(maximumSamples, storedCount)
        var result: [Float] = []
        result.reserveCapacity(amount)
        for _ in 0..<amount {
            result.append(storage[readIndex])
            readIndex = (readIndex + 1) % capacity
            storedCount -= 1
        }
        return result
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        readIndex = 0
        writeIndex = 0
        storedCount = 0
        storage.withUnsafeMutableBufferPointer { buffer in
            for index in buffer.indices { buffer[index] = 0 }
        }
    }
}

public final class PCMBufferCollector: @unchecked Sendable {
    private let metadataLock = NSLock()
    public let buffer: AudioRingBuffer
    public private(set) var latestTimestamp: UInt64 = 0
    public private(set) var sampleRate: Double = 0
    public private(set) var channelCount: Int = 0
    public private(set) var generation: UInt64 = 0

    public init(capacity: Int = 48_000 * 2) {
        self.buffer = AudioRingBuffer(capacity: capacity)
    }

    /// This method is designed for the capture callback: it copies into the
    /// bounded queue and does not allocate an AudioFrame or run DSP work.
    @discardableResult
    public func accept(
        samples: UnsafeBufferPointer<Float>,
        timestamp: UInt64,
        sampleRate: Double,
        channelCount: Int,
        generation: UInt64
    ) -> Int {
        guard metadataLock.try() else { return samples.count }
        defer { metadataLock.unlock() }
        latestTimestamp = timestamp
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.generation = generation
        return buffer.write(samples)
    }

    /// Metadata and PCM are read under one lock; the callback drops rather than waits.
    public func latestWindow(fftSize: Int, hopSize: Int) -> AudioFrame? {
        metadataLock.lock()
        defer { metadataLock.unlock() }
        guard channelCount > 0 else { return nil }
        let count = fftSize * channelCount
        let hop = min(fftSize, hopSize) * channelCount
        let samples = buffer.readLatestWindow(sampleCount: count, retainingSamples: count - hop)
        guard samples.count == count else { return nil }
        return AudioFrame(timestamp: latestTimestamp, sampleRate: sampleRate,
                          channelCount: channelCount, generation: generation,
                          samples: samples, isFresh: latestTimestamp > 0)
    }

    public func reset(generation: UInt64) {
        metadataLock.lock()
        defer { metadataLock.unlock() }
        buffer.reset()
        latestTimestamp = 0
        sampleRate = 0
        channelCount = 0
        self.generation = generation
    }
}

public final class AudioFrameMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: AudioFrame?
    private var acceptsAnyGeneration = true
    public private(set) var generation: UInt64 = 0

    public init() {}

    public func publish(_ frame: AudioFrame) {
        lock.lock()
        defer { lock.unlock() }
        if acceptsAnyGeneration {
            generation = frame.generation
            acceptsAnyGeneration = false
        } else if frame.generation != generation {
            return
        }
        self.frame = frame
    }

    public func latest() -> AudioFrame? {
        lock.lock()
        defer { lock.unlock() }
        return frame
    }

    public func reset(generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        self.generation = generation
        acceptsAnyGeneration = false
        frame = nil
    }
}

public struct AudioAnalyzerConfiguration: Equatable, Sendable {
    /// Preserve approximately 43 ms of frequency context through 192 kHz.
    public static func windowSize(sampleRate: Double) -> Int {
        if sampleRate > 96_000 { return 8_192 }
        if sampleRate > 48_000 { return 4_096 }
        return 2_048
    }

    public var sampleRate: Double
    public var channelCount: Int
    public var isInterleaved: Bool
    public var fftSize: Int
    public var hopSize: Int
    public var silenceThreshold: Float

    public init(
        sampleRate: Double,
        channelCount: Int,
        isInterleaved: Bool,
        fftSize: Int = 2_048,
        hopSize: Int = 512,
        silenceThreshold: Float = 0.0005
    ) {
        precondition(fftSize > 1 && (fftSize & (fftSize - 1)) == 0, "FFT size must be a power of two")
        self.sampleRate = sampleRate
        self.channelCount = max(1, channelCount)
        self.isInterleaved = isInterleaved
        self.fftSize = fftSize
        self.hopSize = max(1, hopSize)
        self.silenceThreshold = max(0, silenceThreshold)
    }
}

public final class AudioAnalyzer {
    public let configuration: AudioAnalyzerConfiguration
    private let bandCount = 64
    private let window: [Float]
#if canImport(Accelerate)
    private let dft: vDSP_DFT_Setup?
#endif

    public init(configuration: AudioAnalyzerConfiguration) {
        self.configuration = configuration
        window = (0..<configuration.fftSize).map {
            Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(configuration.fftSize - 1)))
        }
#if canImport(Accelerate)
        dft = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(configuration.fftSize), .FORWARD)
#endif
    }

    deinit {
#if canImport(Accelerate)
        if let dft { vDSP_DFT_DestroySetup(dft) }
#endif
    }

    public func analyze(samples: [Float], timestamp: UInt64, generation: UInt64) -> AudioFeatures {
        guard samples.count >= configuration.fftSize * configuration.channelCount else {
            return AudioFeatures(
                timestamp: timestamp,
                rms: 0,
                peak: 0,
                bass: 0,
                mids: 0,
                highs: 0,
                bands: [],
                isSilent: true,
                isFresh: false,
                generation: generation
            )
        }

        let mono = makeMonoFrame(from: samples)
        let rms = rootMeanSquare(mono)
        let peak = mono.reduce(0) { max($0, abs($1)) }
        guard rms > configuration.silenceThreshold else {
            return AudioFeatures(
                timestamp: timestamp,
                rms: rms,
                peak: peak,
                bass: 0,
                mids: 0,
                highs: 0,
                bands: Array(repeating: 0, count: bandCount),
                isSilent: true,
                isFresh: true,
                generation: generation
            )
        }

        let magnitudes = fftMagnitudes(mono)
        let bands = makeLogBands(magnitudes: magnitudes)
        return AudioFeatures(
            timestamp: timestamp,
            rms: rms,
            peak: peak,
            bass: normalizedEnergy(magnitudes, low: 20, high: 250),
            mids: normalizedEnergy(magnitudes, low: 250, high: 4_000),
            highs: normalizedEnergy(magnitudes, low: 4_000, high: 16_000),
            bands: bands,
            isSilent: false,
            isFresh: true,
            generation: generation
        )
    }

    private func makeMonoFrame(from samples: [Float]) -> [Float] {
        let channels = max(1, configuration.channelCount)
        let frameStart: Int
        if configuration.isInterleaved {
            frameStart = max(0, samples.count - configuration.fftSize * channels)
        } else {
            frameStart = max(0, samples.count - configuration.fftSize)
        }
        var mono = Array(repeating: Float.zero, count: configuration.fftSize)
        if configuration.isInterleaved {
            let scale = 1 / sqrt(Float(channels))
            for index in 0..<configuration.fftSize {
                let base = frameStart + index * channels
                var sum: Float = 0
                for channel in 0..<channels where base + channel < samples.count {
                    sum += samples[base + channel]
                }
                mono[index] = sum * scale
            }
        } else {
            for index in 0..<configuration.fftSize where frameStart + index < samples.count {
                mono[index] = samples[frameStart + index]
            }
        }
        return mono
    }

    private func rootMeanSquare(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sum = values.reduce(Float.zero) { $0 + $1 * $1 }
        return sqrt(sum / Float(values.count))
    }

    /// Radix-2 FFT kept dependency-free for the spike. The production phase
    /// can replace this routine with vDSP without changing AudioFeatures.
    private func fftMagnitudes(_ input: [Float]) -> [Float] {
        var real = input
        for index in real.indices { real[index] *= window[index] }
#if canImport(Accelerate)
        if let dft {
            let zeros = Array(repeating: Float.zero, count: input.count)
            var outputReal = zeros
            var outputImaginary = zeros
            vDSP_DFT_Execute(dft, real, zeros, &outputReal, &outputImaginary)
            let scale = 4 / Float(input.count * input.count)
            return (0..<(input.count / 2)).map {
                (outputReal[$0] * outputReal[$0] + outputImaginary[$0] * outputImaginary[$0]) * scale
            }
        }
#endif
        var imaginary = Array(repeating: Float.zero, count: input.count)
        var j = 0
        for i in 1..<input.count {
            var bit = input.count >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                real.swapAt(i, j)
            }
        }

        var length = 2
        while length <= input.count {
            let angle = -2 * Double.pi / Double(length)
            let phaseReal = Float(cos(angle))
            let phaseImaginary = Float(sin(angle))
            var blockStart = 0
            while blockStart < input.count {
                var currentReal: Float = 1
                var currentImaginary: Float = 0
                for offset in 0..<(length / 2) {
                    let even = blockStart + offset
                    let odd = even + length / 2
                    let oddReal = real[odd] * currentReal - imaginary[odd] * currentImaginary
                    let oddImaginary = real[odd] * currentImaginary + imaginary[odd] * currentReal
                    let evenReal = real[even]
                    let evenImaginary = imaginary[even]
                    real[even] = evenReal + oddReal
                    imaginary[even] = evenImaginary + oddImaginary
                    real[odd] = evenReal - oddReal
                    imaginary[odd] = evenImaginary - oddImaginary
                    let nextReal = currentReal * phaseReal - currentImaginary * phaseImaginary
                    currentImaginary = currentReal * phaseImaginary + currentImaginary * phaseReal
                    currentReal = nextReal
                }
                blockStart += length
            }
            length <<= 1
        }

        let normalization = 2 / Float(input.count)
        return (0..<(input.count / 2)).map { index in
            let magnitude = sqrt(real[index] * real[index] + imaginary[index] * imaginary[index]) * normalization
            return magnitude * magnitude
        }
    }

    private func frequency(for bin: Int) -> Double {
        Double(bin) * configuration.sampleRate / Double(configuration.fftSize)
    }

    private func normalizedEnergy(_ magnitudes: [Float], low: Double, high: Double) -> Float {
        let nyquist = configuration.sampleRate / 2
        guard low < nyquist else { return 0 }
        let upper = min(high, nyquist)
        let lowerBin = max(1, Int(floor(low * Double(configuration.fftSize) / configuration.sampleRate)))
        let upperBin = min(magnitudes.count - 1, Int(ceil(upper * Double(configuration.fftSize) / configuration.sampleRate)))
        guard upperBin >= lowerBin else { return 0 }
        let power = magnitudes[lowerBin...upperBin].reduce(0, +)
        // FFT magnitudes are normalized to the input frame. Scale into a
        // useful relative 0...1 diagnostic range; this is not calibrated LUFS.
        let result = sqrt(max(0, power)) * 12
        return min(1, max(0, result))
    }

    private func makeLogBands(magnitudes: [Float]) -> [Float] {
        let start = 20.0
        let end = min(16_000.0, configuration.sampleRate / 2)
        guard end > start else { return Array(repeating: 0, count: bandCount) }
        return (0..<bandCount).map { index in
            let low = start * pow(end / start, Double(index) / Double(bandCount))
            let high = start * pow(end / start, Double(index + 1) / Double(bandCount))
            return normalizedEnergy(magnitudes, low: low, high: high)
        }
    }
}

public struct FeatureSmoother: Sendable {
    public var attack: Float
    public var release: Float
    public private(set) var current: AudioFeatures = .settled

    public init(attack: Float = 0.35, release: Float = 0.12) {
        self.attack = min(1, max(0, attack))
        self.release = min(1, max(0, release))
    }

    public mutating func ingest(_ next: AudioFeatures) -> AudioFeatures {
        guard next.isFresh else {
            current = AudioFeatures(
                timestamp: next.timestamp,
                rms: current.rms,
                peak: current.peak,
                bass: current.bass,
                mids: current.mids,
                highs: current.highs,
                bands: current.bands,
                isSilent: true,
                isFresh: false,
                generation: next.generation
            )
            return current
        }

        func approach(_ old: Float, _ new: Float) -> Float {
            let amount = new > old ? attack : release
            return old + (new - old) * amount
        }
        let values = [current.rms, current.peak, current.bass, current.mids, current.highs]
        let targets = [next.rms, next.peak, next.bass, next.mids, next.highs]
        let smoothed = zip(values, targets).map { approach($0.0, $0.1) }
        let bands = zip(current.bands + Array(repeating: 0, count: max(0, next.bands.count - current.bands.count)), next.bands)
            .map { approach($0.0, $0.1) }
        current = AudioFeatures(
            timestamp: next.timestamp,
            rms: smoothed[0],
            peak: smoothed[1],
            bass: smoothed[2],
            mids: smoothed[3],
            highs: smoothed[4],
            bands: bands,
            isSilent: next.isSilent,
            isFresh: next.isFresh,
            generation: next.generation
        )
        return current
    }

    public mutating func reset() {
        current = .settled
    }
}
