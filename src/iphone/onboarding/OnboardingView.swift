import SwiftUI
import WhimCore
import WhimIPhone

struct OnboardingView: View {
    var model: IPhoneModel
    let settings: SettingsProjection?
    @State private var step = 0
    @State private var webhook: WebhookEditor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize

    init(model: IPhoneModel, settings: SettingsProjection?) {
        self.model = model; self.settings = settings
        _webhook = State(initialValue: WebhookEditor(client: model.client))
    }

    var body: some View {
        OnboardingFrame(step: step, back: step == 0 ? nil : { move(to: step - 1) }) {
            Group {
                switch step {
                case 0: OnboardingWelcome()
                case 1: workflow
                default: microphone
                }
            }.id(step).transition(.opacity)
        } actions: {
            switch step {
            case 0:
                Button("Get started", systemImage: "arrow.right") { move(to: 1) }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                if !textSize.isAccessibilitySize { OnboardingPrivacyText() }
            case 1:
                Button("Continue to microphone", systemImage: "arrow.right") { move(to: 2) }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                Button("Skip webhook setup") { move(to: 2) }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            default:
                if model.startupState?.microphone == .notDetermined {
                    Button("Allow microphone", systemImage: "mic") { complete(request: true) }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                } else if microphoneDenied {
                    Button("Open system settings", systemImage: "arrow.up.right") {
                        Task { await model.perform { try await model.client.openSystemSettings() } }
                    }.buttonStyle(OnboardingPrimaryButtonStyle())
                }
                if model.startupState?.microphone == .granted {
                    Button("Start using Whim") { complete(request: false) }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                } else {
                    Button("Continue without microphone") { complete(request: false) }
                        .buttonStyle(OnboardingSecondaryButtonStyle())
                }
            }
        }
        .disabled(model.isPending || !model.captureReady || webhook.isPending)
        .sensoryFeedback(.selection, trigger: step)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding")
    }

    private var workflow: some View {
        VStack(alignment: .leading, spacing: 28) {
            OnboardingSymbol(systemName: "arrow.up.right", caption: "CONNECT")
            OnboardingHeading(title: "Your workflow,\ndirectly.",
                detail: "Send each Note to a destination you control. Your audio goes straight from your device to your webhook.")
            if let settings {
                VStack(alignment: .leading, spacing: 20) {
                    WebhookConfigurationView(model: model, editor: webhook, configuration: settings.webhook, compact: true)
                    Button("Save webhook", systemImage: "checkmark") {
                        Task { await webhook.save(); await model.refresh() }
                    }
                    .whimProminentGlassButton()
                    .disabled(!webhook.isDirty || webhook.isPending)
                }
                .padding(20)
                .background(Color(white: 0.055), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12), lineWidth: 1))
            } else { ProgressView("Loading webhook settings…") }
            Label("Set this up later. Your Notes stay on your device until a destination is ready.", systemImage: "tray")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var microphone: some View {
        VStack(alignment: .leading, spacing: 32) {
            OnboardingSymbol(systemName: "mic", caption: "CAPTURE", isLarge: true)
            OnboardingHeading(title: "Ready when\ninspiration strikes.",
                detail: "A thought, an idea, a reminder. Allow microphone access and capture it before it slips away.")
            VStack(alignment: .leading, spacing: 24) {
                OnboardingBenefit(symbol: "waveform", title: "Only when you record",
                    detail: "You choose when to start. Whim uses your microphone only during a Recording Session.")
                OnboardingBenefit(symbol: "iphone", title: "Saved on your device",
                    detail: "Your Notes are stored locally, even when you’re offline.")
            }
            if microphoneDenied {
                Label("Microphone access is denied. Enable it in system settings, or finish setup for now.", systemImage: "mic.slash")
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 16))
            } else if model.startupState?.microphone == .granted {
                Label("Microphone access is ready.", systemImage: "checkmark.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var microphoneDenied: Bool {
        model.startupState?.microphone == .denied || model.startupState?.microphone == .restricted
    }
    private func move(to destination: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = destination }
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }
    private func complete(request: Bool) {
        Task { await model.perform {
            if request { _ = try await model.client.requestPermission(.microphone) }
            try await model.client.completeOnboarding()
        } }
    }
}

/// Startup and the interactive welcome share their first frame.
struct OnboardingFrame<Content: View, Actions: View>: View {
    let step: Int
    var back: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                ScrollView {
                    content.frame(maxWidth: 480, alignment: .leading)
                        .padding(.horizontal, 28).padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height, alignment: step == 1 ? .top : .center)
                }.scrollDismissesKeyboard(.interactively)
            }
            VStack(spacing: 12) { actions }
                .frame(maxWidth: 480).padding(.horizontal, 28)
                .padding(.top, 20).padding(.bottom, 16)
                .frame(maxWidth: .infinity).background(.black)
                .fixedSize(horizontal: false, vertical: true)
        }.background(.black)
    }

    private var header: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                if let back {
                    Button(action: back) {
                        Image(systemName: "arrow.left").font(.body.weight(.medium))
                            .frame(width: 44, height: 44).whimGlass(in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Back")
                        .accessibilityIdentifier("onboarding-back")
                } else {
                    Image("whim.small").resizable().scaledToFit()
                        .frame(width: 34, height: 24).accessibilityHidden(true)
                }
                Text("whim").font(.title2.weight(.semibold))
                Spacer()
                Text(String(format: "%02d / 03", step + 1))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .accessibilityLabel("Step \(step + 1) of 3")
            }
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Capsule().fill(.white.opacity(index <= step ? 0.85 : 0.15)).frame(height: 2)
                }
            }.accessibilityHidden(true)
        }.padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 8)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

struct OnboardingWelcome: View {
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            LiveWaveformView(isResting: true).frame(height: 100).padding(.horizontal, 12)
                .frame(height: textSize.isAccessibilitySize ? 120 : 160)
                .frame(maxWidth: .infinity).accessibilityHidden(true)
            OnboardingHeading(title: "A place for\nyour thoughts.",
                detail: "Whim stores voice Notes locally on your iPhone and Apple Watch and delivers them directly to your webhook.")
            VStack(alignment: .leading, spacing: 24) {
                OnboardingBenefit(symbol: "lock", title: "Keep it yours",
                    detail: "Local storage. Your destination. You’re in control.")
                OnboardingBenefit(symbol: "hand.tap", title: "Convenient",
                    detail: "Assign the Action Button to Whim, or use its control in Control Center or on the Lock Screen.")
                OnboardingBenefit(symbol: "applewatch", title: "Apple Watch",
                    detail: "Use complications, or add Whim to the Smart Stack for hands-free operation.")
            }
            if textSize.isAccessibilitySize { OnboardingPrivacyText() }
        }
    }
}

private struct OnboardingHeading: View {
    let title: String
    let detail: String
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 38
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: titleSize, weight: .semibold))
                .tracking(-1.2).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(detail).font(.body).foregroundStyle(.secondary)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OnboardingPrivacyText: View {
    var body: some View {
        Text("No account. No cloud storage. No analytics.")
            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct OnboardingBenefit: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.body).frame(width: 44, height: 44)
                .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityElement(children: .combine)
    }
}

private struct OnboardingSymbol: View {
    let systemName: String
    let caption: String
    var isLarge = false
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemName).font(.system(size: isLarge ? 42 : 28, weight: .light))
                .frame(width: isLarge ? 112 : 72, height: isLarge ? 112 : 72)
                .whimGlass(in: RoundedRectangle(cornerRadius: isLarge ? 36 : 24))
            Text(caption).font(.caption2.weight(.medium)).tracking(3).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, isLarge ? 24 : 8).accessibilityHidden(true)
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.labelStyle(.titleOnly).font(.body.weight(.semibold)).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 56).padding(.horizontal, 20).padding(.vertical, 4)
            .foregroundStyle(.black).background(.white, in: Capsule())
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
