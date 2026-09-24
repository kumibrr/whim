import SwiftUI
import WhimCore
import WhimIPhone

enum SettingsSection: String, CaseIterable, Hashable {
    case webhook, audio, titles, permissions, watch
    var title: String {
        switch self {
        case .webhook: "Webhook"
        case .audio: "Audio retention"
        case .titles: "On-device titles"
        case .permissions: "Permissions"
        case .watch: "Apple Watch"
        }
    }
    var symbol: String {
        switch self {
        case .webhook: "link"
        case .audio: "waveform"
        case .titles: "text.bubble"
        case .permissions: "hand.raised"
        case .watch: "applewatch"
        }
    }
}

private let retentionChoices: [(RetentionPolicy, String)] = [(.immediately, "Immediately"), (.oneDay, "1 day"), (.sevenDays, "7 days"), (.thirtyDays, "30 days"), (.ninetyDays, "90 days"), (.never, "Never")]

/// Settings root: one row per section, each opening its own page.
struct PreferencesView: View {
    var model: IPhoneModel
    let settings: SettingsProjection
    @State private var confirm = false
    var body: some View {
        List {
            Section {
                ForEach(SettingsSection.allCases, id: \.self) { section in
                    NavigationLink(value: IPhoneRoute.settingsSection(section)) {
                        HStack {
                            Label(section.title, systemImage: section.symbol)
                            Spacer()
                            Text(summary(section)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(section.title)
                        .accessibilityValue(summary(section))
                    }
                    .accessibilityIdentifier("settings-\(section.rawValue)")
                }
            }
            Section {
                Button("Reset Whim", systemImage: "arrow.counterclockwise", role: .destructive) { confirm = true }
                    .foregroundStyle(.red)
            } footer: {
                Text("Remove all local Notes and restore Whim’s settings.")
            }
            if let error = model.error { WhimErrorText(message: error.message).listRowBackground(Color.clear) }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .disabled(model.isPending)
        .accessibilityIdentifier("preferences")
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $confirm) {
            ConfirmationView(title: "Reset Whim on this iPhone?", message: "This removes all local audio, Notes, history, webhook configuration and credentials. It cannot revoke delivery accepted by your server or erase a disconnected Watch immediately.", confirm: "Confirm reset", error: model.error?.message, onCancel: { confirm = false }, onConfirm: { await model.perform { try await model.client.reset() } })
                .presentationDetents([.medium, .large]).interactiveDismissDisabled(model.isPending)
        }
    }
    private func summary(_ section: SettingsSection) -> String {
        switch section {
        case .webhook: settings.webhook.map { destinationLabel($0.destination) } ?? "Not configured"
        case .audio: retentionChoices.first { $0.0 == settings.preferences.retentionPolicy }?.1 ?? ""
        case .titles: settings.preferences.transcriptionEnabled ? "On" : "Off"
        case .permissions: ""
        case .watch: settings.watch.availability.capitalized
        }
    }
}

/// One settings section; editable sections commit their own draft with Save.
struct SettingsSectionView: View {
    var model: IPhoneModel
    let settings: SettingsProjection
    let section: SettingsSection
    @State private var editor: SettingsEditor
    init(model: IPhoneModel, settings: SettingsProjection, section: SettingsSection) {
        self.model = model; self.settings = settings; self.section = section
        _editor = State(initialValue: SettingsEditor(client: model.client, preferences: settings.preferences))
    }
    private var isEditable: Bool { [.webhook, .audio, .titles].contains(section) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
                if let error = editor.preferencesError ?? model.error { WhimErrorText(message: error.message) }
            }
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.black)
        .disabled(model.isPending || editor.isPending)
        .accessibilityIdentifier("settings-section-\(section.rawValue)")
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if isEditable {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        Task { await editor.save(); await model.refresh() }
                    }
                    .whimProminentGlassButton().tint(.blue)
                    .disabled(!editor.canSave)
                    .accessibilityLabel("Save settings")
                }
            }
        }
    }
    @ViewBuilder private var content: some View {
        switch section {
        case .webhook:
            WebhookConfigurationView(model: model, editor: editor.webhook, configuration: settings.webhook)
        case .audio:
            HStack {
                Text("Keep audio after delivery")
                Spacer()
                Picker("Keep audio", selection: $editor.retentionPolicy) {
                    ForEach(retentionChoices, id: \.0) { policy, label in Text(label).tag(policy) }
                }
                .pickerStyle(.menu).labelsHidden().accessibilityIdentifier("retention-picker")
            }
            footnote("Unsent and recovered Notes are always kept until you delete them. Timeline metadata remains after audio expires.")
        case .titles:
            Toggle("Transcription", isOn: $editor.transcriptionEnabled).accessibilityLabel("Transcription enabled")
            footnote("Only on-device recognition is used. No full transcript is stored.")
            VStack(alignment: .leading, spacing: 6) {
                Text("Transcription language").font(.subheadline).foregroundStyle(.secondary)
                TextField(editor.deviceLanguage, text: $editor.language)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().whimInput("Transcription language")
            }
            footnote("Defaults to your iPhone language.")
        case .permissions:
            permission(.microphone, status: settings.permissions.microphone, title: "Microphone")
            permission(.speech, status: settings.permissions.speech, title: "Speech recognition")
            permission(.notifications, status: settings.permissions.notifications, title: "Notifications")
            footnote("Choose whether notification previews show Note titles on the Lock Screen in system Settings → Notifications → Whim → Show Previews.")
            Button("Notification preview settings", systemImage: "bell.badge") { systemSettings() }.whimGlassButton()
        case .watch:
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
