import Foundation

/// Full-width meter visualization; not PCM samples or a scrolling audio history.
public enum LiveWaveform {
    public static func level(power: Double) -> Double {
        power.isFinite ? max(0, min(1, (power + 60) / 60)) : 0
    }

    public static func displacement(at x: Double, level: Double, tone: Double) -> Double {
        let envelope = pow(sin(.pi * x), 2)
        // Tone changes curvature; volume only scales amplitude. No clock or phase drift.
        let brightness = tone.isFinite ? max(0, min(1, tone)) : 0
        let wave = sin((6 + 6 * brightness) * .pi * x) * 0.7
            + sin((12 + 5 * brightness) * .pi * x) * 0.3
        return level * 0.46 * envelope * wave
    }
}
