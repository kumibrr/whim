import SwiftUI

/// The app's waveform: the logo mark at rest, travelling to a flat line when a
/// Recording Session starts and rising into a voice trace as somebody speaks.
/// Shared by iPhone and Apple Watch; its proportions follow the frame it is given.
public struct LiveWaveformView: View {
    var power: Double
    var tone: Double
    var isResting: Bool
    var identifier: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownLevel = 0.0
    @State private var shownTone = 0.0
    @State private var rest = 1.0
    @State private var isTravelling = false
    @State private var pending: WaveformMeasurement?
    private var level: Double { LiveWaveform.level(power: power) }
    public init(power: Double = -160, tone: Double = 0, isResting: Bool = false,
                accessibilityIdentifier: String = "live-waveform") {
        self.power = power; self.tone = tone; self.isResting = isResting
        self.identifier = accessibilityIdentifier
    }
    public var body: some View {
        GeometryReader { geometry in
            let amplitude = WaveformLayout.amplitude(in: geometry.size)
            let thickness = WaveformLayout.strokeWidth(amplitude: amplitude)
            ZStack {
                WaveformTrace(level: shownLevel, tone: shownTone, rest: rest, amplitude: amplitude)
                    .stroke(.white, style: StrokeStyle(
                        lineWidth: thickness, lineCap: .round, lineJoin: .round))
                AccentDot(rest: rest, amplitude: amplitude, radius: thickness * 0.48)
                    .fill(.white)
            }
            // One layer: where the dot meets the line they must read as one stroke.
            .compositingGroup().opacity(0.9)
        }
        .onAppear {
            rest = isResting ? 1 : 0
            shownLevel = level
            shownTone = tone
        }
        .onChange(of: isResting) { _, resting in travel(toRest: resting) }
        .onChange(of: level) { _, measured in meter(.init(level: measured, tone: tone)) }
        .onChange(of: tone) { _, measured in meter(.init(level: level, tone: measured)) }
        .accessibilityElement()
        .accessibilityLabel(isResting ? "Whim" : "Microphone level")
        .accessibilityValue(isResting ? "" : "\(Int(level * 100)) percent")
        .accessibilityIdentifier(identifier)
    }

    /// The journey owns the waveform while it runs, so a measurement arriving
    /// moments after Record cannot cut the mark's travel short. The last one to
    /// arrive meanwhile is shown as soon as the journey ends.
    private func travel(toRest resting: Bool) {
        let destination = resting ? 1.0 : 0.0
        guard !reduceMotion else { rest = destination; return }
        isTravelling = true
        withAnimation(.easeInOut(duration: 0.25)) {
            rest = destination
        } completion: {
            isTravelling = false
            if let waiting = pending {
                pending = nil
                meter(waiting)
            }
        }
    }

    private func meter(_ measurement: WaveformMeasurement) {
        guard !isTravelling else { pending = measurement; return }
        guard !reduceMotion else {
            shownLevel = measurement.level
            shownTone = measurement.tone
            return
        }
        withAnimation(.easeOut(duration: 0.12)) {
            shownLevel = measurement.level
            shownTone = measurement.tone
        }
    }
}

private struct WaveformMeasurement: Equatable {
    var level: Double
    var tone: Double
}

/// The logo's proportions: height and stroke follow the width, bounded by the frame.
private enum WaveformLayout {
    static func amplitude(in size: CGSize) -> Double {
        min(size.width * 0.14, size.height * 0.46)
    }
    static func strokeWidth(amplitude: Double) -> Double { max(2, amplitude * 0.18) }
}

private struct WaveformTrace: Shape {
    var level: Double
    var tone: Double
    var rest: Double
    var amplitude: Double
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(level, AnimatablePair(tone, rest)) }
        set {
            level = newValue.first
            tone = newValue.second.first
            rest = newValue.second.second
        }
    }
    func path(in rect: CGRect) -> Path {
        let points = LiveWaveform.points(level: level, tone: tone, rest: rest)
        return Path { path in
            for (index, point) in points.enumerated() {
                let place = rect.place(point, amplitude: amplitude)
                if index == 0 { path.move(to: place) } else { path.addLine(to: place) }
            }
        }
    }
}

/// The logo's dot. It grows out of the line with the mark and shrinks away with it.
private struct AccentDot: Shape {
    var rest: Double
    var amplitude: Double
    var radius: Double
    var animatableData: Double {
        get { rest }
        set { rest = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let center = rect.place(LiveWaveform.accent(rest: rest), amplitude: amplitude)
        let size = radius * max(0, min(1, rest))
        return Path(ellipseIn: CGRect(x: center.x - size, y: center.y - size,
                                      width: size * 2, height: size * 2))
    }
}

private extension CGRect {
    func place(_ point: WaveformPoint, amplitude: Double) -> CGPoint {
        CGPoint(x: minX + width * point.x, y: midY - amplitude * point.y)
    }
}

