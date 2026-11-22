import AppKit
import Foundation

/// Synthesizes crisp, subtle, Apple-style tactile micro-sounds in memory (no external audio assets required).
@MainActor
final class SoundFeedbackService {
    var isEnabled: Bool = true

    private let popData: Data
    private let swipeNextData: Data
    private let swipePrevData: Data
    private let tickData: Data

    init() {
        self.popData = Self.synthesizeBubblePop()
        self.swipeNextData = Self.synthesizeSwipe(upward: true)
        self.swipePrevData = Self.synthesizeSwipe(upward: false)
        self.tickData = Self.synthesizeDetentTick()
    }

    /// Warm tactile "пуньк" when clicking an app or opening a menu/window.
    func playPop() {
        guard isEnabled else { return }
        play(data: popData, volume: 0.42)
    }

    /// Smooth directional magnetic swoosh when swiping left/right between folders.
    func playSwipe(forward: Bool) {
        guard isEnabled else { return }
        play(data: forward ? swipeNextData : swipePrevData, volume: 0.36)
    }

    /// Ultra-light mechanical detent click while spinning the 3D cylinder.
    func playTick() {
        guard isEnabled else { return }
        play(data: tickData, volume: 0.22)
    }

    private func play(data: Data, volume: Float) {
        guard let sound = NSSound(data: data) else { return }
        sound.volume = volume
        sound.play()
    }

    // MARK: - Procedural PCM WAV Synthesis (44.1 kHz, 16-bit mono)

    private static func synthesizeBubblePop() -> Data {
        let sampleRate = 44_100
        let duration = 0.068
        let count = Int(Double(sampleRate) * duration)
        var samples = [Int16](repeating: 0, count: count)
        var phase: Double = 0
        var phase2: Double = 0

        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let norm = t / duration
            // Quick pitch rise (460 Hz -> 860 Hz) creates a warm woody/glass "пуньк"
            let freq = 460.0 + 400.0 * pow(norm, 0.55)
            phase += 2.0 * .pi * freq / Double(sampleRate)
            phase2 += 2.0 * .pi * (freq * 2.02) / Double(sampleRate)

            let attack = min(1.0, t / 0.004)
            let decay = exp(-t * 48.0)
            let env = attack * decay

            let wave = sin(phase) * 0.80 + sin(phase2) * 0.20
            let val = max(-1.0, min(1.0, wave * env * 0.85))
            samples[i] = Int16(val * Double(Int16.max))
        }
        return encodeWAV(samples: samples, sampleRate: sampleRate)
    }

    private static func synthesizeSwipe(upward: Bool) -> Data {
        let sampleRate = 44_100
        let duration = 0.075
        let count = Int(Double(sampleRate) * duration)
        var samples = [Int16](repeating: 0, count: count)
        var phase: Double = 0
        var noiseState: UInt32 = upward ? 0x1234_5678 : 0x8765_4321
        var lpNoise: Double = 0

        let startFreq = upward ? 320.0 : 540.0
        let endFreq = upward ? 620.0 : 310.0

        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let norm = t / duration

            // Smooth pitched glide + gentle filtered air whoosh
            let freq = startFreq + (endFreq - startFreq) * (1.0 - pow(1.0 - norm, 2.0))
            phase += 2.0 * .pi * freq / Double(sampleRate)

            // Fast deterministic LCG white noise passed through a soft low-pass filter
            noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
            let white = (Double(Int32(bitPattern: noiseState)) / Double(Int32.max))
            lpNoise = lpNoise * 0.82 + white * 0.18

            let env = sin(.pi * norm) * exp(-norm * 1.4)
            let wave = sin(phase) * 0.58 + lpNoise * 0.42
            let val = max(-1.0, min(1.0, wave * env * 0.85))
            samples[i] = Int16(val * Double(Int16.max))
        }
        return encodeWAV(samples: samples, sampleRate: sampleRate)
    }

    private static func synthesizeDetentTick() -> Data {
        let sampleRate = 44_100
        let duration = 0.022
        let count = Int(Double(sampleRate) * duration)
        var samples = [Int16](repeating: 0, count: count)
        var phase: Double = 0

        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let norm = t / duration
            let freq = 1050.0 - 420.0 * norm
            phase += 2.0 * .pi * freq / Double(sampleRate)

            let attack = min(1.0, t / 0.0015)
            let decay = exp(-t * 150.0)
            let val = max(-1.0, min(1.0, sin(phase) * attack * decay * 0.80))
            samples[i] = Int16(val * Double(Int16.max))
        }
        return encodeWAV(samples: samples, sampleRate: sampleRate)
    }

    private static func encodeWAV(samples: [Int16], sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate * Int(numChannels) * Int(bitsPerSample) / 8)
        let blockAlign = UInt16(numChannels * bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)
        let chunkSize = 36 + dataSize

        var data = Data(capacity: 44 + Int(dataSize))
        func append(_ string: String) { data.append(contentsOf: string.utf8) }
        func appendU32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
        func appendU16(_ v: UInt16) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }

        append("RIFF")
        appendU32(chunkSize)
        append("WAVE")
        append("fmt ")
        appendU32(16)
        appendU16(1) // PCM
        appendU16(numChannels)
        appendU32(UInt32(sampleRate))
        appendU32(byteRate)
        appendU16(blockAlign)
        appendU16(bitsPerSample)
        append("data")
        appendU32(dataSize)

        samples.withUnsafeBufferPointer { buf in
            for sample in buf {
                var le = sample.littleEndian
                withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
            }
        }
        return data
    }
}
