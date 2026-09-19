import SwiftUI
import WhimCore
import WhimIPhone

enum IPhoneRoute: Hashable { case settings, note(NoteID) }
struct IPhoneRootView: View {
    @Bindable var model: IPhoneModel
    var pendingLink: PendingIPhoneLink?
    @Environment(\.scenePhase) private var phase
    @State private var path: [IPhoneRoute] = []
    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let settings = model.settings {
                    if settings.onboardingCompleted { home(settings) }
                    else { OnboardingView(model: model, settings: settings) }
                } else {
                    VStack { Text(model.error?.message ?? "Loading Whim…"); Button("Refresh") { Task { await model.refresh() } } }
                }
            }.navigationDestination(for: IPhoneRoute.self) { route in
                switch route {
                case .settings: if let settings = model.settings { PreferencesView(model: model, settings: settings) }
                case .note(let id): NoteDetailView(root: model, noteID: id)
                }
            }.toolbar(.hidden, for: .navigationBar)
        }.task { await model.start() }
            .onChange(of: phase) { _, phase in if phase == .active { Task { await model.refresh() } } }
            .onChange(of: model.settings?.onboardingCompleted) { _, completed in if completed == false { path = [] } }
            .onChange(of: model.feedback) { _, feedback in
                if !feedback.isEmpty { UIAccessibility.post(notification: .announcement, argument: feedback) }
            }
            .onChange(of: model.recording?.sessionID) { old, new in
                if old != new { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            }
            .task(id: pendingLink?.id) {
                guard let url = pendingLink?.url else { return }
                guard ["whim", "app.whim.ios"].contains(url.scheme ?? "") else { return }
                let parts = ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" })
                if parts.first == "settings" { path = [.settings] }
                else if parts.first == "note", let raw = parts.last, let id = UUID(uuidString: raw) { path = [.note(NoteID(rawValue: id))] }
                else { path = [] }
            }
    }
    private func home(_ settings: SettingsProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Settings") { path.append(.settings) }.padding(.horizontal, 24)
            if !model.feedback.isEmpty { Text(model.feedback).foregroundStyle(.secondary).padding(.horizontal, 24) }
            if model.recording != nil { RecorderView(model: model) }
            else { TimelineView(model: model) { path.append(.note($0)) } }
            if let error = model.error { WhimErrorText(message: error.message).padding(.horizontal, 24) }
            if model.offersContextualPermissions && model.recording == nil && (settings.permissions.speech == .notDetermined || settings.permissions.notifications == .notDetermined) {
                VStack(alignment: .leading) {
                    Text("Your Note is saved. Optional permissions help with titles and delivery alerts.")
                    if settings.permissions.speech == .notDetermined { Button("Enable on-device titles") { permission(.speech) } }
                    if settings.permissions.notifications == .notDetermined { Button("Enable delivery alerts") { permission(.notifications) } }
                    Button("Later") { model.dismissContextualPermissions() }
                }.padding(20)
            }
            if settings.permissions.microphone != .granted {
                Button("Microphone settings") { Task { await model.perform { try await model.client.openSystemSettings() } } }
            }
        }
    }
    private func permission(_ kind: PermissionKind) { Task { await model.perform { _ = try await model.client.requestPermission(kind) } } }
}
