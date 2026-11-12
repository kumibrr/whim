import SwiftUI
import WhimCore
import WhimIPhone

enum SettingsSection: String, CaseIterable, Hashable {
    case webhook, webhookErrors = "webhook-errors", audio, titles, permissions, watch, quickCapture = "quick-capture"
    var title: String {
        switch self {
        case .quickCapture: "Configure action button"
        case .webhook: "Webhook"
        case .webhookErrors: "Webhook errors"
        case .audio: "Audio retention"
        case .titles: "On-device titles"
        case .permissions: "Permissions"
        case .watch: "Apple Watch"
        }
    }
    var symbol: String {
        switch self {
        case .quickCapture: "button.vertical.left.press"
        case .webhook: "link"
        case .webhookErrors: "exclamationmark.triangle"
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
    @Environment(\.dynamicTypeSize) private var typeSize
    var model: IPhoneModel
    let settings: SettingsProjection
    @State private var confirm = false
    var body: some View {
        List {
            Section {
                ForEach(SettingsSection.allCases.filter {
                    $0 != .webhookErrors && $0 != .quickCapture
                }, id: \.self) { section in
                    settingsLink(section)
                }
            }
            // Control Center/Lock Screen and Watch complication setup are hidden for now.
            if QuickCaptureGuide.currentRoute == .actionButton {
                Section("Shortcuts") {
                    settingsLink(.quickCapture)
                }
            }
            Section {
                Button("Reset Whim", systemImage: "arrow.counterclockwise", role: .destructive) { confirm = true }
                    .buttonStyle(.automatic)
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
        .alert("Reset Whim on this iPhone?", isPresented: $confirm) {
            Button("Confirm reset", role: .destructive) {
                Task { await model.perform { try await model.client.reset() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all local audio, Notes, history, webhook configuration and credentials. It cannot revoke delivery accepted by your server or erase a disconnected Watch immediately.")
        }
    }
    private func settingsLink(_ section: SettingsSection) -> some View {
        NavigationLink(value: IPhoneRoute.settingsSection(section)) {
            WhimLabeledValue {
                Label(section.title, systemImage: section.symbol)
            } value: {
                if !summary(section).isEmpty {
                    Text(summary(section)).foregroundStyle(.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(section.title)
            .accessibilityValue(summary(section))
        }
        .accessibilityIdentifier("settings-\(section.rawValue)")
    }
    private func summary(_ section: SettingsSection) -> String {
        switch section {
        case .webhook: settings.webhook.map { destinationLabel($0.destination) } ?? "Not configured"
        case .audio: retentionChoices.first { $0.0 == settings.preferences.retentionPolicy }?.1 ?? ""
        case .titles: settings.preferences.transcriptionEnabled ? "On" : "Off"
        case .webhookErrors, .permissions, .quickCapture: ""
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
    @State private var errorLog: WebhookErrorLog
    init(model: IPhoneModel, settings: SettingsProjection, section: SettingsSection) {
        self.model = model; self.settings = settings; self.section = section
        _editor = State(initialValue: SettingsEditor(client: model.client, preferences: settings.preferences))
        _errorLog = State(initialValue: WebhookErrorLog(client: model.client))
    }
    private var isEditable: Bool { [.webhook, .audio, .titles, .watch].contains(section) }
    var body: some View {
        WhimContent(spacing: WhimSpacing.group) {
            content
            if let error = editor.preferencesError ?? errorLog.error ?? model.error {
                WhimErrorText(message: error.message)
            }
        }
        .disabled(model.isPending || editor.isPending)
        .accessibilityIdentifier("settings-section-\(section.rawValue)")
        .onAppear { if section == .permissions { model.markPermissionsReviewed() } }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .task(id: model.revision) { if section == .webhookErrors { await errorLog.refresh() } }
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
        case .quickCapture:
            QuickCaptureSetupView()
        case .webhook:
            WebhookConfigurationView(model: model, editor: editor.webhook, configuration: settings.webhook)
            sectionShortcut(.webhookErrors, label: "View webhook errors")
        case .webhookErrors:
            if errorLog.entries.isEmpty {
                Text("No webhook errors.").foregroundStyle(.secondary)
            }
            ForEach(errorLog.entries) { entry in webhookError(entry) }
            footnote("Failed deliveries and configuration tests, with secrets redacted. Delivery entries are removed with their Note; test entries are cleared by Reset Whim.")
        case .audio:
            AudioRetentionControl(editor: editor)
            footnote("Unsent and recovered Notes are always kept until you delete them. Timeline metadata remains after audio expires.")
        case .titles:
            OnDeviceTitlesControl(editor: editor)
            footnote("Only on-device recognition is used. No full transcript is stored.")
            VStack(alignment: .leading, spacing: WhimSpacing.field) {
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
            WatchRecordingControls(autoStopEnabled: $editor.watchAutoStopEnabled,
                silenceDurationSeconds: $editor.watchSilenceDurationSeconds)
            footnote("After you speak, Whim stops, saves, and sends when it detects silence. Applies to Apple Watch recordings.")
            Text(watchRecordingSynchronization)
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("watch-recording-sync-status")
            Divider()
            Text("Watch synchronization \(settings.watch.availability).")
            let details = WatchConnectionDetails(settings: settings.watch)
            if let cause = details.cause {
                Text(cause).font(.callout).accessibilityIdentifier("watch-unavailability-reason")
            }
            if let recovery = details.recovery {
                Text(recovery).font(.callout).accessibilityIdentifier("watch-unavailability-recovery")
            }
            Button("Refresh status", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                .whimGlassButton().accessibilityIdentifier("watch-refresh-status")
            TechnicalDetailsView(rows: details.technicalRows, identifier: "watch-technical-details") { EmptyView() }
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
    private var watchRecordingSynchronization: String {
        if editor.isDirty { return "Save to update your Apple Watch." }
        switch settings.watch.recordingPreferencesState {
        case "synchronized": return "Recording settings synchronized."
        case "pending": return "Recording settings will sync with your Apple Watch."
        default: return "Recording settings will sync when your Apple Watch is available."
        }
    }
    private func sectionShortcut(_ target: SettingsSection, label: String) -> some View {
        NavigationLink(value: IPhoneRoute.settingsSection(target)) {
            Label(label, systemImage: target.symbol)
        }
        .whimGlassButton()
        .accessibilityIdentifier("shortcut-\(target.rawValue)")
    }
    private func webhookError(_ entry: WebhookErrorLog.Entry) -> some View {
        VStack(alignment: .leading, spacing: WhimSpacing.field) {
            HStack {
                Text("⚠ \(entry.status)").fontWeight(.semibold)
                Spacer()
                Text(TimelineFormat.date(entry.failedAt)).font(.footnote).foregroundStyle(.secondary)
            }
            Text(entry.message).font(.callout.monospaced()).textSelection(.enabled)
                .accessibilityIdentifier("webhook-error-message")
            Text(destinationLabel(entry.destination)).font(.footnote).foregroundStyle(.secondary)
            if entry.noteID == nil { Text(entry.noteTitle).font(.footnote) }
            if let noteID = entry.noteID {
                NavigationLink(value: IPhoneRoute.note(noteID)) {
                    Label(entry.noteTitle, systemImage: "waveform").font(.footnote).lineLimit(1)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .whimGlass(in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Note \(entry.noteTitle)")
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Contain children so the entry identifier does not replace webhook-error-message.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("webhook-error")
    }
    private func footnote(_ text: String) -> some View { Text(text).font(.footnote).foregroundStyle(.secondary) }
    private func permission(_ kind: PermissionKind, status: PermissionStatus, title: String) -> some View {
        WhimLabeledValue {
            Text(title)
        } value: {
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

/// The same native controls are used in Settings and the update onboarding screen.
struct WatchRecordingControls: View {
    @Binding var autoStopEnabled: Bool
    @Binding var silenceDurationSeconds: Int

    var body: some View {
        Group {
            Toggle("Auto-stop after silence", isOn: $autoStopEnabled)
                .frame(minHeight: 44)
                .accessibilityIdentifier("watch-auto-stop-enabled")
            VStack(alignment: .leading, spacing: WhimSpacing.field) {
                WhimLabeledValue {
                    Text("Silence duration")
                } value: {
                    Text("\(silenceDurationSeconds) seconds").monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(silenceDurationSeconds) },
                    set: { silenceDurationSeconds = Int($0.rounded()) }),
                    in: 2...10, step: 1) {
                    Text("Silence duration")
                } minimumValueLabel: {
                    Text("2 s")
                } maximumValueLabel: {
                    Text("10 s")
                }
                .frame(minHeight: 44)
                .disabled(!autoStopEnabled)
                .accessibilityValue("\(silenceDurationSeconds) seconds")
                .accessibilityIdentifier("watch-silence-duration")
            }
        }
    }
}
/// Settings controls edit the preference draft until the user saves.
struct AudioRetentionControl: View {
    @Bindable var editor: SettingsEditor
    var body: some View {
        WhimLabeledValue {
            Text("Keep audio after delivery")
        } value: {
            Picker("Keep audio", selection: $editor.retentionPolicy) {
                ForEach(retentionChoices, id: \.0) { policy, label in Text(label).tag(policy) }
            }
            .pickerStyle(.menu).labelsHidden().accessibilityIdentifier("retention-picker")
        }
    }
}

struct OnDeviceTitlesControl: View {
    @Bindable var editor: SettingsEditor
    var body: some View {
        Toggle("Transcription", isOn: $editor.transcriptionEnabled)
            .accessibilityLabel("Transcription enabled")
    }
}
