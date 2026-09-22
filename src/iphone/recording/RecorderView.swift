import SwiftUI
import WhimIPhone

struct CaptureHomeView: View {
    var model: IPhoneModel
    var glassNamespace: Namespace.ID
    var settings: () -> Void
    var body: some View {
        VStack {
            HStack {
                if model.areFailuresCollapsed {
                    ErrorNotificationsButton(model: model)
                } else {
                    Text("whim").font(.system(size: 22, weight: .medium, design: .rounded))
                        .tracking(-1).foregroundStyle(.white.opacity(0.45)).accessibilityHidden(
                            true)
                }
                Spacer()
                Button(action: settings) {
                    Image(systemName: "gearshape").font(.system(size: 20, weight: .regular))
                        .frame(width: 48, height: 48).whimGlass(in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Settings")
                    .accessibilityIdentifier("settings-button")
            }.padding(.horizontal, 24).padding(.top, 12)
            Spacer()
            if !model.feedback.isEmpty {
                Text(model.feedback).font(.footnote).foregroundStyle(.secondary).padding(
                    .bottom, 20)
            }
            Button {
                Task { await model.startRecording() }
            } label: {
                Circle().fill(.white).frame(width: 26, height: 26)
                    .frame(width: 80, height: 80).whimGlass(in: Circle())
                    .captureGlassIdentity("capture", in: glassNamespace)
            }.buttonStyle(.plain).accessibilityLabel("Record a Whim")
                .accessibilityIdentifier("record-button")
                .disabled(model.isRecordingPending || !model.captureReady)
            if !model.captureReady { ProgressView("Preparing recording…") }
            Button {
                model.openHistory()
            } label: {
                VStack(spacing: 10) {
                    Text("scroll to see previous notes.").font(.system(size: 12))
                    Image(systemName: "chevron.up").font(
                        .system(size: 9, weight: .semibold))
                }.foregroundStyle(.white.opacity(0.5)).padding(.top, 22).padding(
                    .bottom, 12
                )
                .frame(minHeight: 48)
            }.buttonStyle(.plain).accessibilityLabel("Show previous Notes")
                .accessibilityIdentifier("history-hint")
        }.accessibilityElement(children: .contain).accessibilityIdentifier("whim-home")
    }
}

struct RecorderView: View {
    var model: IPhoneModel
    var glassNamespace: Namespace.ID
    var body: some View {
        if let recording = model.recording {
            let remaining = max(0, recording.maximumDurationSeconds - floor(model.elapsedSeconds))
            VStack(spacing: 12) {
                Text("RECORDING").font(.system(size: 11, weight: .medium)).tracking(3)
                    .foregroundStyle(.secondary).padding(.top, 32)
                Text(TimelineFormat.duration(seconds: model.elapsedSeconds))
                    .font(.system(size: 32, weight: .light, design: .monospaced))
                    .monospacedDigit()
                ProgressView(
                    value: min(model.elapsedSeconds, recording.maximumDurationSeconds),
                    total: recording.maximumDurationSeconds
                )
                .tint(.white).frame(width: 100)
                .accessibilityLabel("Recording progress")
                .accessibilityValue(
                    "\(TimelineFormat.duration(seconds: model.elapsedSeconds)) of \(TimelineFormat.duration(seconds: recording.maximumDurationSeconds))"
                )
                if remaining <= recording.warningLeadSeconds {
                    Text("\(Int(remaining)) seconds remaining").font(.footnote)
                }
                Spacer()
                Text("Stop saves your Note and starts delivery.").font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 24).padding(
                        .bottom, 8)
                Button {
                    Task { await model.stopRecording() }
                } label: {
                    RoundedRectangle(cornerRadius: 5).fill(.red).frame(
                        width: 24, height: 24
                    )
                    .frame(width: 80, height: 80).whimGlass(in: Circle())
                    .captureGlassIdentity("capture", in: glassNamespace)
                }.buttonStyle(.plain).accessibilityLabel("Stop recording")
                    .accessibilityIdentifier("stop-recording")
                Button(role: .destructive) {
                    Task { await model.discardRecording() }
                } label: {
                    if #available(iOS 26, *) {
                        discardLabel.whimGlass(in: Capsule())
                            .captureGlassIdentity("discard", in: glassNamespace)
                    } else {
                        discardLabel
                    }
                }.buttonStyle(.plain).accessibilityLabel("Discard recording")
                    .accessibilityIdentifier("discard-recording")
                    .padding(.bottom, 12)
            }.frame(maxWidth: .infinity).overlay(alignment: .topLeading) {
                if model.areFailuresCollapsed {
                    ErrorNotificationsButton(model: model).padding(.leading, 24).padding(.top, 12)
                }
            }.disabled(model.isRecordingPending).accessibilityElement(children: .contain)
                .accessibilityIdentifier("recorder-panel")
        }
    }
    private var discardLabel: some View {
        Text("Discard")
            .font(.body.weight(.semibold))
            .foregroundStyle(.red)
            .frame(minWidth: 120, minHeight: 56)
            .contentShape(Rectangle())
    }
}

/// The app's waveform: the logo mark at rest, travelling to a flat line when a
/// Recording Session starts and rising into a voice trace as somebody speaks.
struct LiveWaveformView: View {
    var power = -160.0
    var tone = 0.0
    var isResting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownLevel = 0.0
    @State private var shownTone = 0.0
    @State private var rest = 1.0
    @State private var isTravelling = false
    @State private var pending: WaveformMeasurement?
    private var level: Double { LiveWaveform.level(power: power) }
    var body: some View {
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
        .accessibilityIdentifier("live-waveform")
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

private struct ErrorNotificationsButton: View {
    var model: IPhoneModel
    var body: some View {
        Button { model.expandFailures() } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                Text("\(model.failureCount)").monospacedDigit()
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, 14).frame(minHeight: 48)
            .whimGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.failureCount == 1 ? "1 notification" : "\(model.failureCount) notifications")
        .accessibilityHint("Show error details")
        .accessibilityIdentifier("error-notifications")
    }
}
