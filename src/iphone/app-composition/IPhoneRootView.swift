import SwiftUI
import WhimCore
import WhimIPhone

enum IPhoneRoute: Hashable { case settings, settingsSection(SettingsSection), note(NoteID) }
private enum IPhoneSheet: String, Identifiable { case history, appUpdate; var id: String { rawValue } }
struct IPhoneRootView: View {
    @AppStorage("onboarding.quickCapture.v1.acknowledged", store: UserDefaults(suiteName: WhimProductionComposition.preferenceSuiteName)) private var setupAcknowledged = false
    @Bindable var model: IPhoneModel
    var pendingLink: PendingIPhoneLink?
    @Environment(\.scenePhase) private var phase
    @Namespace private var captureGlassNamespace
    @Namespace private var failureNamespace
    @State private var path: [IPhoneRoute] = []
    @State private var handlingLink = false
    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.onboardingCompleted { home }
                else { OnboardingView(model: model, settings: model.settings, setupAcknowledged: $setupAcknowledged) }
            }
            // The stack's root does not inherit insets applied outside NavigationStack.
            .modifier(IPhoneFailurePresentation(model: model,
                enabled: path.isEmpty && !model.isHistoryPresented
                    && (model.onboardingCompleted || model.visibleFailure?.action != .microphoneSettings),
                allowsCollapse: model.onboardingCompleted, morphNamespace: failureNamespace, configureWebhook: openWebhookSettings))
            .navigationDestination(for: IPhoneRoute.self) { route in
                switch route {
                case .settings: if let settings = model.settings { PreferencesView(model: model, settings: settings) }
                case .settingsSection(let section):
                    if let settings = model.settings { SettingsSectionView(model: model, settings: settings, section: section) }
                case .note(let id): NoteDetailView(root: model, noteID: id)
                }
            }.toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: sheetPresentation) { sheet in sheetContent(sheet) }
        .onChange(of: model.isHistoryPresented) { old, new in
            if !old && new { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        }
        .task { await model.start() }
            .onChange(of: phase) { _, phase in Task { await model.setSceneActive(phase == .active) } }
            .onChange(of: model.settings?.onboardingCompleted) { _, completed in if completed == false { path = [] } }
            .onChange(of: model.feedback) { _, feedback in
                if !feedback.isEmpty { UIAccessibility.post(notification: .announcement, argument: feedback) }
            }
            .onChange(of: model.recording?.sessionID) { old, new in
                if old != new { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                if new != nil { path = [] }
            }
            .task(id: pendingLink?.id) {
                guard let url = pendingLink?.url else { return }
                guard ["whim", "app.whim.ios"].contains(url.scheme ?? "") else { return }
                handlingLink = true
                defer { handlingLink = false }
                await model.closeHistory()
                #if DEBUG
                // Installed journeys exercise the production shortcut with fixture audio.
                if url.host == "record-shortcut", ProcessInfo.processInfo.arguments.contains("-WhimFixtureAudio") {
                    await model.perform { _ = try await RecordWhimIntent(runtime: .shared).perform() }
                    return
                }
                #endif
                guard await model.prepareForNavigation() else { return }
                let parts = ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" })
                if parts.first == "settings" {
                    path = [.settings] + (parts.dropFirst().first.flatMap(SettingsSection.init(rawValue:)).map { [.settingsSection($0)] } ?? [])
                }
                else if parts.first == "note", let raw = parts.last, let id = UUID(uuidString: raw) { path = [.note(NoteID(rawValue: id))] }
                else { path = [] }
            }
    }
    private var sheetPresentation: Binding<IPhoneSheet?> {
        Binding(get: {
            if model.isHistoryPresented { return .history }
            if path.isEmpty, !handlingLink, phase == .active, model.offersAppUpdate { return .appUpdate }
            return nil
        }, set: { sheet in
            if sheet == nil, model.isHistoryPresented { Task { await model.closeHistory() } }
        })
    }
    @ViewBuilder private func sheetContent(_ sheet: IPhoneSheet) -> some View {
        switch sheet {
        case .history: HistorySheet(model: model)
        case .appUpdate:
            if let update = model.appUpdate.pendingUpdate {
                AppUpdateView(model: model.appUpdate, update: update)
            }
        }
    }
    private var home: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // One waveform outlives both states, so the mark can travel to the
            // recording line and back instead of being swapped out.
            GeometryReader { geometry in
                LiveWaveformView(power: model.peakPowerDBFS, tone: model.recordingTone,
                                 isResting: model.recording == nil)
                    .frame(height: 160)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.45)
            }
            CaptureGlassContainer(isRecording: model.recording != nil) {
                if model.recording != nil {
                    RecorderView(model: model, glassNamespace: captureGlassNamespace, failureNamespace: failureNamespace)
                        .transition(.identity)
                } else {
                    CaptureHomeView(model: model, glassNamespace: captureGlassNamespace, failureNamespace: failureNamespace, reviewPermissions: {
                        Task { if await model.prepareForNavigation() { path = [.settings, .settingsSection(.permissions)] } }
                    }) {
                        Task { if await model.prepareForNavigation() { path.append(.settings) } }
                    }
                    .transition(.identity)
                }
            }
        }.simultaneousGesture(DragGesture(minimumDistance: 18)
            .onEnded { value in
                guard model.canBrowse, !model.isHistoryPresented else { return }
                if value.translation.height < -100 || value.predictedEndTranslation.height < -200 {
                    model.openHistory()
                }
            })
    }
    private func openWebhookSettings() {
        Task {
            await model.closeHistory()
            if await model.prepareForNavigation() { path = [.settings, .settingsSection(.webhook)] }
        }
    }
}

/// The error card belongs to the capture home; Settings and history report failures inline.
struct IPhoneFailurePresentation: ViewModifier {
    var model: IPhoneModel
    var enabled = true
    var allowsCollapse = false
    var morphNamespace: Namespace.ID? = nil
    var configureWebhook: () -> Void
    @State private var showsStorageInstructions = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top) {
            if enabled, !(allowsCollapse && model.areFailuresCollapsed), let failure = model.visibleFailure {
                WhimErrorContainer(message: failure.message, actionLabel: failure.actionLabel,
                    busy: model.isResolvingError || model.isPending || model.isRecordingPending,
                    action: { resolve(failure) },
                    dismiss: [.history, .settings, .maintenance].contains(failure.operation) ? { model.dismissAuxiliaryError() } : nil,
                    collapse: allowsCollapse ? {
                        withAnimation(.failureNotificationsMorph(reduceMotion: reduceMotion)) { model.collapseFailures() }
                    } : nil)
                    .failureNotificationsMorph(in: morphNamespace)
                    .padding(.horizontal, WhimSpacing.page).padding(.top, 8)
            }
        }
        .alert("Free up storage", isPresented: $showsStorageInstructions) {
            Button("Check again") { Task { await model.retryVisibleFailure() } }
            Button("Close", role: .cancel) {}
        } message: {
            Text("Open iPhone Settings > General > iPhone Storage and remove items you no longer need. Then return to Whim and check again.")
        }
    }
    private func resolve(_ failure: ActionableFailure) {
        switch failure.action {
        case .retry: Task { await model.retryVisibleFailure() }
        case .microphoneSettings, .liveActivitySettings: Task { await model.perform { try await model.client.openSystemSettings() } }
        case .storageInstructions: showsStorageInstructions = true
        case .configureWebhook: configureWebhook()
        }
    }
}
