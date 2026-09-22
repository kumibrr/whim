import Foundation

/// A point on the waveform. `x` runs 0...1 across the full width; `y` is a signed
/// fraction of the curve's tallest excursion, positive upward.
public struct WaveformPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// The drawable waveform: one continuous cubic curve plus the logo's floating dot.
public struct WaveformCurve: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        public let control1: WaveformPoint
        public let control2: WaveformPoint
        public let end: WaveformPoint
        public init(control1: WaveformPoint, control2: WaveformPoint, end: WaveformPoint) {
            self.control1 = control1; self.control2 = control2; self.end = end
        }
        func point(at u: Double, from start: WaveformPoint) -> WaveformPoint {
            let v = 1 - u
            let weights = [v * v * v, 3 * v * v * u, 3 * v * u * u, u * u * u]
            let xs = [start.x, control1.x, control2.x, end.x]
            let ys = [start.y, control1.y, control2.y, end.y]
            return WaveformPoint(x: zip(weights, xs).reduce(0) { $0 + $1.0 * $1.1 },
                                 y: zip(weights, ys).reduce(0) { $0 + $1.0 * $1.1 })
        }
    }
    public let start: WaveformPoint
    public let segments: [Segment]
    /// Centre of the logo dot. Its radius follows the stroke, so only the centre is geometry.
    public let accent: WaveformPoint
}

/// Full-width voice meter: the Whim logo at rest, a voice trace while recording.
/// Neither is PCM samples or a scrolling audio history.
public enum LiveWaveform {
    /// A quiet room must read as silence and ordinary speech must fill the trace,
    /// so the meter spans the loudness of a human voice rather than the full scale.
    public static let voiceFloorDBFS = -48.0
    public static let voiceCeilingDBFS = -6.0

    public static func level(power: Double) -> Double {
        guard power.isFinite else { return 0 }
        return max(0, min(1, (power - voiceFloorDBFS) / (voiceCeilingDBFS - voiceFloorDBFS)))
    }

    /// The app's default waveform: the logo curve, shown while nothing is recording.
    public static let resting = WaveformCurve(start: WaveformPoint(x: 0, y: 0),
                                              segments: logo, accent: accent)

    /// The voice itself, drawn as a waveform rather than as the logo. Loudness scales
    /// the trace and measured tonal brightness redistributes its heights. Every factor
    /// but the wave itself stays positive, so the trace only ever moves up and down —
    /// its crossings never slide sideways. No clock, so a steady voice holds still.
    public static func displacement(at x: Double, level: Double, tone: Double) -> Double {
        let amplitude = level.isFinite ? max(0, min(1, level)) : 0
        let brightness = tone.isFinite ? max(0, min(1, tone)) : 0
        let position = max(0, min(1, x))
        let envelope = pow(sin(.pi * position), 2)
        let wave = sin(2 * .pi * cyclesAcrossTheWidth * position)
        // A fixed contour, slower than the wave itself, gives the trace the uneven
        // rise and fall of speech while treating crests and troughs alike.
        let contour = 0.62 + 0.38 * sin(2 * .pi * position - 0.4 * .pi)
        // Brighter voices hold the tallest crest and push the others down.
        let voice = 1 - 0.45 * brightness * (0.5 + 0.5 * cos(5 * .pi * position))
        return amplitude * envelope * contour * voice * wave
    }

    /// Blends the voice trace into the resting logo. `rest` is 0 while recording and
    /// 1 when idle; values between are the transition between the two.
    public static func points(level: Double, tone: Double, rest: Double) -> [WaveformPoint] {
        let blend = rest.isFinite ? max(0, min(1, rest)) : 0
        return (0...traceSteps).map { step in
            let progress = Double(step) / Double(traceSteps)
            let live = WaveformPoint(x: progress,
                                     y: displacement(at: progress, level: level, tone: tone))
            guard blend > 0 else { return live }
            let mark = logoTrace[step]
            return WaveformPoint(x: live.x + (mark.x - live.x) * blend,
                                 y: live.y + (mark.y - live.y) * blend)
        }
    }

    /// The logo's dot, which belongs to the resting mark and arrives with it.
    public static func accent(rest: Double) -> WaveformPoint {
        let blend = rest.isFinite ? max(0, min(1, rest)) : 0
        return WaveformPoint(x: accent.x, y: accent.y * blend)
    }

    private static let cyclesAcrossTheWidth = 3.0
    private static let traceSteps = 480

    /// The logo sampled at the same resolution as the trace, so one can travel to
    /// the other point by point.
    private static let logoTrace: [WaveformPoint] = (0...traceSteps).map { step in
        let progress = Double(step) / Double(traceSteps) * Double(logo.count)
        let index = min(logo.count - 1, Int(progress))
        let u = progress - Double(index)
        let from = index == 0 ? WaveformPoint(x: 0, y: 0) : logo[index - 1].end
        return logo[index].point(at: u, from: from)
    }

    private static let accent = WaveformPoint(x: 0.57333, y: 0.38690)

    /// The logo artwork, normalized from `Whim.icon`'s waveform path.
    private static let logo: [WaveformCurve.Segment] = [
        .init(control1: WaveformPoint(x: 0.04167, y: 0.00000), control2: WaveformPoint(x: 0.08333, y: 0.00000), end: WaveformPoint(x: 0.12500, y: 0.00000)),
        .init(control1: WaveformPoint(x: 0.15417, y: 0.00000), control2: WaveformPoint(x: 0.17083, y: 0.05952), end: WaveformPoint(x: 0.18750, y: 0.23810)),
        .init(control1: WaveformPoint(x: 0.20417, y: 0.41667), control2: WaveformPoint(x: 0.21500, y: 0.65476), end: WaveformPoint(x: 0.23167, y: 0.65476)),
        .init(control1: WaveformPoint(x: 0.25000, y: 0.65476), control2: WaveformPoint(x: 0.25167, y: 0.35714), end: WaveformPoint(x: 0.25667, y: 0.02976)),
        .init(control1: WaveformPoint(x: 0.26250, y: -0.35714), control2: WaveformPoint(x: 0.27250, y: -0.50595), end: WaveformPoint(x: 0.28750, y: -0.50595)),
        .init(control1: WaveformPoint(x: 0.30417, y: -0.50595), control2: WaveformPoint(x: 0.31833, y: -0.23810), end: WaveformPoint(x: 0.33167, y: 0.02976)),
        .init(control1: WaveformPoint(x: 0.34417, y: 0.27976), control2: WaveformPoint(x: 0.35583, y: 0.32738), end: WaveformPoint(x: 0.36500, y: 0.10714)),
        .init(control1: WaveformPoint(x: 0.37417, y: -0.13095), control2: WaveformPoint(x: 0.38417, y: -0.43452), end: WaveformPoint(x: 0.40000, y: -0.43452)),
        .init(control1: WaveformPoint(x: 0.41917, y: -0.43452), control2: WaveformPoint(x: 0.43333, y: -0.05952), end: WaveformPoint(x: 0.44333, y: 0.35714)),
        .init(control1: WaveformPoint(x: 0.45333, y: 0.80357), control2: WaveformPoint(x: 0.46000, y: 1.00000), end: WaveformPoint(x: 0.47167, y: 1.00000)),
        .init(control1: WaveformPoint(x: 0.48583, y: 1.00000), control2: WaveformPoint(x: 0.48583, y: 0.70238), end: WaveformPoint(x: 0.48000, y: 0.36905)),
        .init(control1: WaveformPoint(x: 0.47500, y: 0.08333), control2: WaveformPoint(x: 0.47083, y: -0.16071), end: WaveformPoint(x: 0.47000, y: -0.32143)),
        .init(control1: WaveformPoint(x: 0.46917, y: -0.45238), control2: WaveformPoint(x: 0.47500, y: -0.47619), end: WaveformPoint(x: 0.48417, y: -0.35119)),
        .init(control1: WaveformPoint(x: 0.49667, y: -0.17857), control2: WaveformPoint(x: 0.50583, y: 0.05952), end: WaveformPoint(x: 0.51917, y: 0.05952)),
        .init(control1: WaveformPoint(x: 0.53500, y: 0.05952), control2: WaveformPoint(x: 0.53500, y: -0.19643), end: WaveformPoint(x: 0.53833, y: -0.35119)),
        .init(control1: WaveformPoint(x: 0.54083, y: -0.48810), control2: WaveformPoint(x: 0.54833, y: -0.50000), end: WaveformPoint(x: 0.55750, y: -0.35119)),
        .init(control1: WaveformPoint(x: 0.56500, y: -0.22619), control2: WaveformPoint(x: 0.56833, y: -0.08929), end: WaveformPoint(x: 0.57000, y: 0.05357)),
        .init(control1: WaveformPoint(x: 0.57167, y: -0.20833), control2: WaveformPoint(x: 0.57333, y: -0.44048), end: WaveformPoint(x: 0.58500, y: -0.44048)),
        .init(control1: WaveformPoint(x: 0.59750, y: -0.44048), control2: WaveformPoint(x: 0.60667, y: -0.17857), end: WaveformPoint(x: 0.61750, y: 0.00000)),
        .init(control1: WaveformPoint(x: 0.62833, y: 0.17857), control2: WaveformPoint(x: 0.64083, y: 0.19048), end: WaveformPoint(x: 0.65083, y: 0.02976)),
        .init(control1: WaveformPoint(x: 0.66167, y: -0.13690), control2: WaveformPoint(x: 0.66667, y: -0.38095), end: WaveformPoint(x: 0.67750, y: -0.38095)),
        .init(control1: WaveformPoint(x: 0.68917, y: -0.38095), control2: WaveformPoint(x: 0.69667, y: -0.10714), end: WaveformPoint(x: 0.70750, y: 0.03571)),
        .init(control1: WaveformPoint(x: 0.71750, y: 0.16667), control2: WaveformPoint(x: 0.72917, y: 0.15476), end: WaveformPoint(x: 0.73917, y: -0.00595)),
        .init(control1: WaveformPoint(x: 0.75000, y: -0.17857), control2: WaveformPoint(x: 0.75500, y: -0.42262), end: WaveformPoint(x: 0.76917, y: -0.42262)),
        .init(control1: WaveformPoint(x: 0.78583, y: -0.42262), control2: WaveformPoint(x: 0.80000, y: -0.25000), end: WaveformPoint(x: 0.81583, y: -0.11905)),
        .init(control1: WaveformPoint(x: 0.83167, y: 0.01190), control2: WaveformPoint(x: 0.84833, y: 0.00000), end: WaveformPoint(x: 0.87083, y: 0.00000)),
        .init(control1: WaveformPoint(x: 0.91389, y: 0.00000), control2: WaveformPoint(x: 0.95694, y: 0.00000), end: WaveformPoint(x: 1.00000, y: 0.00000)),
    ]
}
