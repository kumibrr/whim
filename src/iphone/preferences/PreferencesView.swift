import SwiftUI
import WhimCore
import WhimIPhone

private enum SettingsSection: String, CaseIterable, Hashable {
    case webhook = "Webhook", audio = "Audio", titles = "Titles", permissions = "Access", watch = "Watch", reset = "Reset"
    static let jumpTargets: [SettingsSection] = [.webhook, .audio, .titles, .permissions, .watch]
}

struct PreferencesView: View {
    var model: IPhoneModel
    let settings: SettingsProjection
    @State private var editor: SettingsEditor
    @State private var confirm = false
    @State private var section: SettingsSection = .webhook
    @State private var position = ScrollPosition(idType: SettingsSection.self)
    init(model: IPhoneModel, settings: SettingsProjection) {
        self.model = model; self.settings = settings
        _editor = State(initialValue: SettingsEditor(client: model.client, preferences: settings.preferences))
    }
    private let choices: [(RetentionPolicy, String)] = [(.immediately, "Immediately"), (.oneDay, "1 day"), (.sevenDays, "7 days"), (.thirtyDays, "30 days"), (.ninetyDays, "90 days"), (.never, "Never")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                settingsSection(.webhook, title: "Webhook") {
                    WebhookConfigurationView(model: model, editor: editor.webhook, configuration: settings.webhook)
                }
                settingsSection(.audio, title: "Audio retention") {
                    HStack {
                        Text("Keep audio after delivery")
                        Spacer()
                        Picker("Keep audio", selection: $editor.retentionPolicy) {
                            ForEach(choices, id: \.0) { policy, label in Text(label).tag(policy) }
                        }
                        .pickerStyle(.menu).labelsHidden().accessibilityIdentifier("retention-picker")
                    }
                    footnote("Unsent and recovered Notes are always kept until you delete them. Timeline metadata remains after audio expires.")
                }
                settingsSection(.titles, title: "On-device titles") {
                    Toggle("Transcription", isOn: $editor.transcriptionEnabled).accessibilityLabel("Transcription enabled")
                    footnote("Only on-device recognition is used. No full transcript is stored.")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Transcription language").font(.subheadline).foregroundStyle(.secondary)
                        TextField(editor.deviceLanguage, text: $editor.language)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().whimInput("Transcription language")
                    }
                    footnote("Defaults to your iPhone language.")
                }
                settingsSection(.permissions, title: "Permissions") {
                    permission(.microphone, status: settings.permissions.microphone, title: "Microphone")
                    permission(.speech, status: settings.permissions.speech, title: "Speech recognition")
                    permission(.notifications, status: settings.permissions.notifications, title: "Notifications")
                    footnote("Choose whether notification previews show Note titles on the Lock Screen in system Settings → Notifications → Whim → Show Previews.")
                    Button("Notification preview settings", systemImage: "bell.badge") { systemSettings() }.whimGlassButton()
                }
                settingsSection(.watch, title: "Apple Watch") {
                    Text("Watch synchronization \(settings.watch.availability).")
                    footnote("Last synchronized: \(settings.watch.lastSynchronizedAt.map(TimelineFormat.date) ?? "Not yet synchronized")")
                    if settings.watch.resetState == "pending" {
                        Text("Reset pending on Apple Watch. It will finish after reconnection.").foregroundStyle(.secondary)
                    }
                    if settings.watch.resetState == "synchronized" {
                        Text("Reset completed on both devices.").foregroundStyle(.secondary)
                    }
                    footnote("A disconnected Watch cannot be erased immediately.")
                }
                settingsSection(.reset, title: "Reset") {
                    footnote("Remove all local Notes and restore Whim’s settings.")
                    Button("Reset Whim", systemImage: "arrow.counterclockwise", role: .destructive) { confirm = true }
                        .whimGlassButton().tint(.red)
                }
                if let error = editor.preferencesError ?? model.error { WhimErrorText(message: error.message) }
            }
            .scrollTargetLayout()
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
        }
        .scrollPosition($position)
        .onChange(of: position.viewID(type: SettingsSection.self)) { _, id in
            if let id, SettingsSection.jumpTargets.contains(id) { section = id }
        }
        .whimTopBar {
            Picker("Section", selection: Binding(get: { section }, set: { target in
                section = target
                withAnimation { position.scrollTo(id: target, anchor: .top) }
            })) {
                ForEach(SettingsSection.jumpTargets, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20).padding(.vertical, 8)
            .frame(maxWidth: 600)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.black)
        .disabled(model.isPending || editor.isPending)
        .accessibilityIdentifier("preferences")
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") {
                    Task { await editor.save(); await model.refresh() }
                }
                .whimProminentGlassButton().tint(.blue)
                .disabled(!editor.canSave)
                .accessibilityLabel("Save settings")
            }
        }
        .sheet(isPresented: $confirm) {
            ConfirmationView(title: "Reset Whim on this iPhone?", message: "This removes all local audio, Notes, history, webhook configuration and credentials. It cannot revoke delivery accepted by your server or erase a disconnected Watch immediately.", confirm: "Confirm reset", error: model.error?.message, onCancel: { confirm = false }, onConfirm: { await model.perform { try await model.client.reset() } })
                .presentationDetents([.medium, .large]).interactiveDismissDisabled(model.isPending)
        }
    }
    private func settingsSection<Content: View>(_ id: SettingsSection, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(id)
    }
    private func footnote(_ text: String) -> some View { Text(text).font(.footnote).foregroundStyle(.secondary) }
    private func permission(_ kind: PermissionKind, status: PermissionStatus, title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            if status == .notDetermined {
                Button("Allow") { Task { await model.perform { _ = try await model.client.requestPermission(kind) } } }
                    .whimGlassButton().accessibilityLabel("Allow \(kind.rawValue)")
            } else if status == .denied || status == .restricted {
                Button("Open settings") { systemSettings() }
                    .whimGlassButton().accessibilityLabel("Open \(kind.rawValue) settings")
            } else {
                Text(status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
    }
    private func systemSettings() { Task { await model.perform { try await model.client.openSystemSettings() } } }
}
