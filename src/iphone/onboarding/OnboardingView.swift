import SwiftUI
import AVFoundation
import WhimCore
import WhimIPhone

struct OnboardingView: View {
    var model: IPhoneModel
    let settings: SettingsProjection?
    @AppStorage("onboarding.v1.step", store: UserDefaults(suiteName: WhimProductionComposition.appGroupIdentifier)) private var savedStep = 0
    @Binding private var setupAcknowledged: Bool
    @AppStorage("onboarding.quickCapture.v1.step", store: UserDefaults(suiteName: WhimProductionComposition.appGroupIdentifier)) private var upgradeStep = 3
    let setupOnly: Bool
    private var step: Int { QuickCaptureGuide.onboardingStep(saved: setupOnly ? upgradeStep : savedStep, setupOnly: setupOnly) }
    @State private var setupPage = 0
    @State private var webhook: WebhookEditor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize

    init(model: IPhoneModel, settings: SettingsProjection?, setupOnly: Bool = false, setupAcknowledged: Binding<Bool> = .constant(false)) {
        self._setupAcknowledged = setupAcknowledged
        self.setupOnly = setupOnly
        self.model = model; self.settings = settings
        _webhook = State(initialValue: WebhookEditor(client: model.client))
    }

    var body: some View {
        OnboardingFrame(step: step, totalSteps: 4, back: step == 0 || (setupOnly && step == 3) || (step == 2 && model.startupState?.microphone == .notDetermined) ? nil : { move(to: step - 1) }) {
            Group {
                switch step {
                case 0: OnboardingWelcome()
                case 1: workflow
                case 2: microphone
                default: QuickCaptureSetupView(onPageChange: { setupPage = $0 })
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
            case 2:
                if model.startupState?.microphone == .notDetermined {
                    Button("Continue", systemImage: "arrow.right") { complete(request: true) }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                } else {
                    if microphoneDenied {
                        Button("Open system settings", systemImage: "arrow.up.right") {
                            Task { await model.perform { try await model.client.openSystemSettings() } }
                        }.buttonStyle(OnboardingPrimaryButtonStyle())
                    }
                    if model.startupState?.microphone == .granted {
                        Button("Continue to setup") { complete(request: false) }
                            .buttonStyle(OnboardingPrimaryButtonStyle())
                    } else {
                        Button("Continue") { complete(request: false) }
                            .buttonStyle(OnboardingSecondaryButtonStyle())
                    }
                }
            default:
                if QuickCaptureGuide.currentRoute == .actionButton && setupPage == 1 {
                    Button("Continue") { finish() }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                } else {
                    Button("Skip for now") { finish() }
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
            OnboardingWorkflowHeading()
            if let settings {
                WebhookConfigurationView(model: model, editor: webhook, configuration: settings.webhook, compact: true)
                    .padding(20)
                    .background(Color(white: 0.055), in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12), lineWidth: 1))
            } else { ProgressView("Loading webhook settings…") }
            Link(destination: URL(string: "https://github.com/kumibrr/whim/blob/main/docs/webhook-contract-v1.md#reference-receiver")!) {
                Label("Set up a server", systemImage: "arrow.up.right")
            }.whimGlassButton().accessibilityIdentifier("onboarding-server-setup")
            Label("Set this up later. Your Notes stay on your device until a destination is ready.", systemImage: "tray")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var microphone: some View {
        VStack(alignment: .leading, spacing: 32) {
            OnboardingMicrophoneHeading()
            if microphoneDenied {
                Label("Enable microphone access in Settings to record.", systemImage: "mic.slash")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var microphoneDenied: Bool {
        model.startupState?.microphone == .denied || model.startupState?.microphone == .restricted
    }
    private func move(to destination: Int) {
        Task {
            if step == 1 { await webhook.saveIfNeeded(); await model.refresh() }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                if setupOnly { upgradeStep = destination } else { savedStep = destination }
            }
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }
    private func complete(request: Bool) {
        Task {
            await model.perform {
                if request { _ = try await model.client.requestPermission(.microphone) }
            }
            move(to: 3)
        }
    }
    private func finish() {
        // Acknowledge while this view is mounted, before completion can replace it.
        setupAcknowledged = true
        guard !setupOnly else { return }
        Task { await model.perform { try await model.client.completeOnboarding() } }
    }

}

/// Startup and the interactive welcome share their first frame.
struct OnboardingFrame<Content: View, Actions: View>: View {
    let step: Int
    var totalSteps: Int = 4
    var back: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                ScrollView {
                    content.frame(maxWidth: 480, alignment: .leading)
                        .padding(.horizontal, WhimSpacing.page).padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height, alignment: step == 1 ? .top : .center)
                }.scrollDismissesKeyboard(.interactively)
            }
            VStack(spacing: 12) { actions }
                .frame(maxWidth: 480).padding(.horizontal, WhimSpacing.page)
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
                Text(String(format: "%02d / %02d", step + 1, totalSteps))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .accessibilityLabel("Step \(step + 1) of \(totalSteps)")
            }
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule().fill(.white.opacity(index <= step ? 0.85 : 0.15)).frame(height: 2)
                }
            }.accessibilityHidden(true)
        }.padding(.horizontal, WhimSpacing.page).padding(.top, 12).padding(.bottom, 8)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

struct OnboardingWelcome: View {
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
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

struct OnboardingWorkflowHeading: View {
    var body: some View {
        OnboardingHeading(title: "Your workflow,\ndirectly.",
            detail: "Send each Note to a destination you control. Your audio goes straight from your device to your webhook.")
    }
}

struct OnboardingMicrophoneHeading: View {
    var body: some View {
        OnboardingHeading(title: "Always ready to record",
            detail: "Whim uses your microphone only when you record.")
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

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.labelStyle(.titleOnly).font(.body.weight(.semibold)).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 56).padding(.horizontal, WhimSpacing.page).padding(.vertical, 4)
            .foregroundStyle(.white).whimGlass(in: Capsule())
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44).whimGlass(in: Capsule())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}


/// A short walkthrough with reserved slots for setup photos or videos. Assignments remain in Apple's system UI.
struct QuickCaptureSetupView: View {
    @State private var page = 0
    var isWatch = false
    var onPageChange: (Int) -> Void = { _ in }
    @State private var controlCenter = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let route = QuickCaptureGuide.currentRoute
    private var actionButton: Bool { route == .actionButton && !isWatch }

    private var titles: [String] {
        if isWatch { return ["A Note from your wrist", "Make room for Whim", "Tap. Talk. Done."] }
        if actionButton { return ["A button for your thoughts", "Set up your Action button"] }
        if controlCenter { return ["One swipe away", "Add Whim", "Ready when you are"] }
        return ["Capture from your Lock Screen", "Make room for Whim", "Ready when you are"]
    }
    private var details: [String] {
        if isWatch { return [
            "Install Whim from the Watch app on iPhone. Open it on your Watch and allow microphone access.",
            "Hold your watch face, tap Edit, then swipe to Complications. Choose a slot that supports Whim.",
            "Select Record a Whim and press the Digital Crown. Tap the complication to record; tap Stop in Whim to finish."
        ] }
        if actionButton { return [
            "Your iPhone has an Action button. Set it up once, then press and hold to capture a thought.",
            "Open Settings → Action Button → Controls → Choose a Control. Select Whim’s Record a Whim control. Press and hold to record; invoke it again to stop and save your Note."
        ] }
        if controlCenter { return [
            "Open Control Center, then touch and hold an empty area to edit your controls.",
            "Tap Add a Control. Search for Whim and choose Record a Whim.",
            "Tap the Whim control to start recording. Tap it again to stop and save your Note."
        ] }
        return [
            "Unlock your iPhone, then hold the Lock Screen. Tap Customize → Lock Screen.",
            "Remove a bottom control with the minus button. Tap the empty slot and search for Whim.",
            "Choose Record a Whim, then tap Done. Use the control to start recording, and again to stop and save."
        ]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(isWatch ? "Apple Watch" : actionButton ? "Action button" : controlCenter ? "Control Center" : "Lock Screen")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(page + 1) of \(titles.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let name = QuickCaptureGuide.mediaName(route: route, isWatch: isWatch, page: page),
               let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
                SetupDemoVideo(url: url, title: titles[page])
                    .frame(height: page == 0 ? 230 : 300)
                    .id(name)
            } else { mediaPlaceholder }
            VStack(alignment: .leading, spacing: 12) {
                Text(titles[page]).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(details[page]).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("setup-instruction")
            HStack(spacing: 16) {
                if page > 0 && !actionButton {
                    Button("Previous") { advance(-1) }.buttonStyle(OnboardingSecondaryButtonStyle())
                }
                if page < titles.count - 1 {
                    Button(page == 0 ? "Show me how" : "Next step", systemImage: "arrow.right") { advance(1) }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                } else if !actionButton {
                    Button("Read again", systemImage: "arrow.counterclockwise") { page = 0 }
                        .buttonStyle(OnboardingSecondaryButtonStyle())
                }
            }
            if page == titles.count - 1 {
                Text("Allow microphone access before trying it. Your first Note is saved normally.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if route == .lockScreen && !isWatch {
                Button(controlCenter ? "Use the Lock Screen instead" : "Use Control Center instead") {
                    controlCenter.toggle(); page = 0
                }.font(.subheadline).foregroundStyle(.white)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isWatch ? "watch-capture-setup" : "quick-capture-setup")
        .onAppear { onPageChange(page) }
        .onChange(of: page) { _, value in onPageChange(value) }
    }
    private func advance(_ offset: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { page += offset }
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    private var mediaPlaceholder: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(white: 0.055))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(white: 0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
            }
            .overlay {
                VStack(spacing: 8) {
                    Text("Setup demo").font(.headline)
                    Text("Image or short video").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 230)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Setup demo placeholder, step \(page + 1)")
            .accessibilityIdentifier("setup-media-placeholder")
    }
}


private struct SetupDemoVideo: View {
    let url: URL
    let title: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var playing = false
    @State private var replay = 0

    var body: some View {
        SetupDemoPlayer(url: url, playing: playing && scenePhase == .active, replay: replay)
            .overlay(alignment: .bottomTrailing) {
                if !playing {
                Button {
                    replay += 1
                    playing = true
                } label: {
                    Label("Play again", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(.black.opacity(0.7), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityIdentifier("replay-setup-demo")
                .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title + " video demonstration")
            .accessibilityIdentifier("setup-demo-video")
            .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { notification in
                guard let item = notification.object as? AVPlayerItem,
                      let asset = item.asset as? AVURLAsset, asset.url == url else { return }
                playing = false
            }
            .onAppear { playing = !reduceMotion }
            .onDisappear { playing = false }
            .onChange(of: reduceMotion) { _, reduced in if reduced { playing = false } }
    }
}

private struct SetupDemoPlayer: UIViewRepresentable {
    let url: URL
    let playing: Bool
    let replay: Int

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        let player = AVPlayer()
        var replay = 0
        init(url: URL) {
            super.init(frame: .zero)
            backgroundColor = .black
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.actionAtItemEnd = .pause
            let playerLayer = layer as! AVPlayerLayer
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
    func makeUIView(context: Context) -> PlayerView { PlayerView(url: url) }
    func updateUIView(_ view: PlayerView, context: Context) {
        if view.replay != replay {
            view.replay = replay
            view.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if playing { view.player.play() } else { view.player.pause() }
    }
    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.player.pause()
        view.player.replaceCurrentItem(with: nil)
    }
}
