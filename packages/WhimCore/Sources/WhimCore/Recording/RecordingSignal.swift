import Foundation

/// Amplitude and tonal brightness measured from mono PCM. Neither depends on time.
/// Brightness is measured over the human voice band so that room rumble and hiss
/// do not steer the meter.
public struct RecordingSignal: Sendable, Equatable {
    public let peakPowerDBFS: Float
    public let tone: Float

    /// Quieter than a person speaking near the device: no voice to describe.
    private static let voiceFloorDBFS: Float = -50
    private static let voiceBandLowHz = 100.0
    private static let voiceBandHighHz = 2000.0
    private static let rumbleCutoffHz = 85.0
    private static let hissCutoffHz = 3000.0

    public static func measure(_ samples: [Float], sampleRate: Double) -> Self {
        let silence = Self(peakPowerDBFS: -160, tone: 0)
        guard samples.count > 1, sampleRate.isFinite, sampleRate > 0,
              samples.allSatisfy({ $0.isFinite }) else { return silence }
        let peak = samples.map { abs($0) }.max() ?? 0
        guard peak > 0.000001 else { return silence }
        let power = max(-160, min(0, 20 * log10(peak)))
        guard power > voiceFloorDBFS else { return .init(peakPowerDBFS: power, tone: 0) }
        let voice = voiceBand(samples, sampleRate: sampleRate)
        var energy = 0.0
        var differenceEnergy = 0.0
        for index in 1..<voice.count {
            let a = voice[index - 1]
            let b = voice[index]
            energy += a * a + b * b
            differenceEnergy += (b - a) * (b - a)
        }
        guard energy > 0 else { return .init(peakPowerDBFS: power, tone: 0) }
        // Normalized first-difference energy measures spectral brightness, independent
        // of gain. For a sinusoid it maps to its frequency; speech includes harmonics.
        let frequency = acos(max(-1, min(1, 1 - differenceEnergy / energy))) * sampleRate / (2 * .pi)
        let span = log2(voiceBandHighHz / voiceBandLowHz)
        let tone = max(0, min(1, log2(max(voiceBandLowHz, frequency) / voiceBandLowHz) / span))
        return .init(peakPowerDBFS: power, tone: Float(tone))
    }

    /// Attenuates rumble below the speech band and hiss above it. One-pole sections
    /// primed from the samples themselves keep a steady vowel steady no matter where
    /// a buffer starts.
    private static func voiceBand(_ samples: [Float], sampleRate: Double) -> [Double] {
        var values = samples.map(Double.init)
        for _ in 0..<2 { highPass(&values, cutoff: rumbleCutoffHz, sampleRate: sampleRate) }
        for _ in 0..<4 { lowPass(&values, cutoff: hissCutoffHz, sampleRate: sampleRate) }
        return values
    }

    private static func coefficient(cutoff: Double, sampleRate: Double) -> Double {
        let factor = 2 * .pi * cutoff / sampleRate
        return max(0, min(1, factor / (1 + factor)))
    }

    private static func lowPass(_ values: inout [Double], cutoff: Double, sampleRate: Double) {
        let alpha = coefficient(cutoff: cutoff, sampleRate: sampleRate)
        var state = values[0]
        for index in values.indices {
            state += alpha * (values[index] - state)
            values[index] = state
        }
    }

    private static func highPass(_ values: inout [Double], cutoff: Double, sampleRate: Double) {
        let alpha = coefficient(cutoff: cutoff, sampleRate: sampleRate)
        var state = values.reduce(0, +) / Double(values.count)
        for index in values.indices {
            state += alpha * (values[index] - state)
            values[index] -= state
        }
    }
}
