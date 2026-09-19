import Foundation

/// Amplitude and tonal brightness measured from mono PCM. Neither depends on time.
public struct RecordingSignal: Sendable, Equatable {
    public let peakPowerDBFS: Float
    public let tone: Float

    public static func measure(_ samples: [Float], sampleRate: Double) -> Self {
        let silence = Self(peakPowerDBFS: -160, tone: 0)
        guard samples.count > 1, sampleRate.isFinite, sampleRate > 0,
              samples.allSatisfy({ $0.isFinite }) else { return silence }
        let peak = samples.map { abs($0) }.max() ?? 0
        guard peak > 0.000001 else { return silence }
        let power = max(-160, min(0, 20 * log10(peak)))
        guard power > -60 else { return .init(peakPowerDBFS: power, tone: 0) }
        let mean = samples.reduce(0.0) { $0 + Double($1) } / Double(samples.count)
        var energy = 0.0
        var differenceEnergy = 0.0
        for index in 1..<samples.count {
            let a = Double(samples[index - 1]) - mean
            let b = Double(samples[index]) - mean
            energy += a * a + b * b
            differenceEnergy += (b - a) * (b - a)
        }
        guard energy > 0 else { return .init(peakPowerDBFS: power, tone: 0) }
        // Normalized first-difference energy measures spectral brightness, independent
        // of gain. For a sinusoid it maps to its frequency; speech includes harmonics.
        let frequency = acos(max(-1, min(1, 1 - differenceEnergy / energy))) * sampleRate / (2 * .pi)
        let tone = max(0, min(1, log2(max(80, frequency) / 80) / log2(4000.0 / 80)))
        return .init(peakPowerDBFS: power, tone: Float(tone))
    }
}
