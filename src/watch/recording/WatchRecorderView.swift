import SwiftUI
import WhimCore

struct WatchCaptureView: View {
    @Bindable var model: WatchModel
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var controlDiameter: CGFloat { model.visibleFailure == nil ? 72 : 48 }

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

            VStack(spacing: model.visibleFailure == nil ? 8 : 4) {
                if model.recording != nil {
                    if model.visibleFailure == nil {
                    Text("RECORDING")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("watch-recorder")
                    }
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
        .safeAreaInset(edge: .top, spacing: 4) {
            if let failure = model.visibleFailure {
                WatchErrorContainer(failure: failure,
                    busy: model.isResolvingError || model.captureBusy,
                    retry: { Task { await model.retryVisibleFailure() } },
                    dismiss: [.history, .settings, .maintenance].contains(failure.operation) ? { model.dismissAuxiliaryError() } : nil)
                    .padding(.horizontal, 8).padding(.top, 30)
            }
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
        if !model.captureReady {
            ProgressView("Preparing…")
        } else if model.permission == .notDetermined {
            VStack(spacing: 8) {
                Text("Microphone access is required to capture a Note.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                if model.permission == .notDetermined {
                    Button("Allow microphone") { Task { await model.requestPermission() } }

                }
            }
        } else if model.permission != .granted {
            EmptyView()
        } else if model.recording != nil {
            Button { Task { await model.stop() } } label: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.red)
                    .frame(width: 22, height: 22)
                    .frame(width: controlDiameter, height: controlDiameter)
                    .watchGlass(in: Circle())
                    .modifier(WatchCaptureGlassIdentity(id: "capture", namespace: glassNamespace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording")
            .accessibilityIdentifier("watch-stop")
            .handGestureShortcut(.primaryAction)
            .disabled(model.captureBusy)
        } else {
            Button { Task { await model.record() } } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
                    .frame(width: controlDiameter, height: controlDiameter)
                    .watchGlass(in: Circle())
                    .modifier(WatchCaptureGlassIdentity(id: "capture", namespace: glassNamespace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Record a Whim")
            .accessibilityIdentifier("watch-record")
            .handGestureShortcut(.primaryAction)
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

struct WatchErrorContainer: View {
    let failure: ActionableFailure
    var busy = false
    let retry: () -> Void
    var dismiss: (() -> Void)? = nil
    @State private var instructions = false
    private var needsInstructions: Bool { failure.action != .retry }
    private var message: String {
        failure.action == .microphoneSettings ? "Allow microphone access to record." : failure.message
    }
    var body: some View {
        Button {
            if needsInstructions { instructions = true } else { retry() }
        } label: {
            HStack(spacing: 6) {
                Text(message).font(.caption2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if busy { ProgressView() }
                else { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .watchGlass(in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).disabled(busy)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(message)
        .accessibilityHint(needsInstructions ? "Show instructions" : failure.actionLabel)
        .accessibilityValue(busy ? "Working" : "")
        .accessibilityIdentifier("startup-error")
        .accessibilityActions {
            if let dismiss { Button("Dismiss error", action: dismiss) }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
            if !busy, abs(value.translation.width) > 40, abs(value.translation.width) > abs(value.translation.height) * 2 {
                dismiss?()
            }
        })
            .sheet(isPresented: $instructions) {
                ScrollView {
                    VStack(spacing: 12) {
                        Text(failure.action == .microphoneSettings ? "On Apple Watch, open Settings > Privacy & Security > Microphone and allow Whim." : failure.action == .configureWebhook ? "Open Whim on your iPhone, then Settings, to configure and test your webhook." : "Open the Watch app on iPhone, then General > Storage. Remove items you no longer need, then return to Whim.")
                        Button("Check again") { instructions = false; retry() }
                        Button("Close") { instructions = false }
                    }.padding()
                }
            }
    }
}

struct WatchStartupShell: View {
    var failure: ActionableFailure?
    var busy = false
    let retry: () -> Void
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Rectangle().fill(.white).frame(height: 1)
            VStack {
                if let failure { WatchErrorContainer(failure: failure, busy: busy, retry: retry).padding(.top, 30) }
                Spacer()
                if failure == nil { ProgressView("Preparing…") }
            }.padding(8)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("watch-capture")
    }
}
