import SwiftUI

struct WatchCaptureView: View {
    @Bindable var model: WatchModel
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if #available(watchOS 26, *) {
            GlassEffectContainer(spacing: 8) { captureContent }
                .animation(reduceMotion || reduceTransparency ? nil : .smooth(duration: 0.35),
                           value: model.recording != nil)
        } else {
            captureContent
        }
    }

    private var captureContent: some View {
        ZStack {
            Color.black
            WatchWaveformView(power: model.recording == nil ? -160 : model.peakPowerDBFS)
                .frame(height: 110)

            VStack(spacing: 8) {
                if model.recording != nil {
                    Text("RECORDING")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("watch-recorder")
                    Text(Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 18, weight: .light, design: .monospaced))
                        .monospacedDigit()
                        .accessibilityIdentifier("watch-elapsed")
                } else {
                    Text("whim")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .accessibilityHidden(true)
                }

                Spacer()
                if model.recording != nil && model.warned {
                    Text("Stopping at five minutes")
                        .font(.caption2)
                        .accessibilityIdentifier("watch-limit-warning")
                }
                captureControl
                if #unavailable(watchOS 26) { Spacer() }

                if model.recording != nil {
                    Button(role: .destructive) {
                        Task { await model.discard() }
                    } label: {
                        if #available(watchOS 26, *) {
                            discardLabel.watchGlass(in: Capsule())
                                .modifier(WatchCaptureGlassIdentity(id: "discard", namespace: glassNamespace))
                        } else {
                            discardLabel
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watch-discard")
                    .disabled(model.captureBusy)
                } else if model.permission == .granted {
                    VStack(spacing: 3) {
                        Text("scroll for previous notes")
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .accessibilityLabel("Scroll for previous Notes")
                    .accessibilityIdentifier("watch-history-hint")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch-capture")
    }

    private var discardLabel: some View {
        Text("Discard")
            .font(.body.weight(.semibold))
            .foregroundStyle(.red)
            .frame(minWidth: 100, minHeight: 44)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var captureControl: some View {
        if model.permission != .granted {
            VStack(spacing: 8) {
                Text("Microphone access is required to capture a Note.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                if model.permission == .notDetermined {
                    Button("Allow microphone") { Task { await model.requestPermission() } }
                } else {
                    Text("On Apple Watch, open Settings > Privacy & Security > Microphone and allow Whim.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
            }
        } else if model.recording != nil {
            Button { Task { await model.stop() } } label: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.red)
                    .frame(width: 22, height: 22)
                    .frame(width: 72, height: 72)
                    .watchGlass(in: Circle())
                    .modifier(WatchCaptureGlassIdentity(id: "capture", namespace: glassNamespace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording")
            .accessibilityIdentifier("watch-stop")
            .disabled(model.captureBusy)
        } else {
            Button { Task { await model.record() } } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
                    .frame(width: 72, height: 72)
                    .watchGlass(in: Circle())
                    .modifier(WatchCaptureGlassIdentity(id: "capture", namespace: glassNamespace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Record a Whim")
            .accessibilityIdentifier("watch-record")
            .disabled(model.captureBusy)
        }
    }
}

private struct WatchWaveformView: View {
    let power: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var level: Double { power.isFinite ? max(0, min(1, (power + 60) / 60)) : 0 }

    var body: some View {
        WatchReactiveLine(level: level)
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
            .accessibilityLabel("Microphone level")
            .accessibilityValue("\(Int(level * 100)) percent")
            .accessibilityIdentifier("watch-waveform")
    }
}

private struct WatchReactiveLine: Shape {
    var level: Double
    var animatableData: Double { get { level } set { level = newValue } }

    func path(in rect: CGRect) -> Path {
        Path { path in
            for step in 0...120 {
                let x = Double(step) / 120
                let envelope = pow(sin(.pi * x), 2)
                let wave = sin(8 * .pi * x) * 0.7 + sin(18 * .pi * x) * 0.3
                let point = CGPoint(x: rect.width * x,
                    y: rect.midY + level * rect.height * 0.42 * envelope * wave)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}

private struct WatchGlass<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(white: 0.12), in: shape)
                .overlay(shape.stroke(.white.opacity(0.28), lineWidth: 0.5))
        } else if #available(watchOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.22), lineWidth: 0.5))
        }
    }
}

private extension View {
    func watchGlass<S: Shape>(in shape: S) -> some View { modifier(WatchGlass(shape: shape)) }
}


private struct WatchCaptureGlassIdentity: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(watchOS 26, *) {
            content.glassEffectID(id, in: namespace)
                .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        } else {
            content
        }
    }
}
