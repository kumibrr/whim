import SwiftUI
import WhimCore
import WhimIPhone
struct PreferencesView: View {
    var model: IPhoneModel
    let settings: SettingsProjection
    @State private var language: String
    @State private var confirm = false
    init(model: IPhoneModel, settings: SettingsProjection) {
        self.model = model; self.settings = settings
        _language = State(initialValue: settings.preferences.transcriptionLocaleIdentifier ?? "")
    }
    private let choices: [(RetentionPolicy, String)] = [(.immediately, "Immediately"), (.oneDay, "1 day"), (.sevenDays, "7 days"), (.thirtyDays, "30 days"), (.ninetyDays, "90 days"), (.never, "Never")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Make Whim your own.")
                    .font(.subheadline).foregroundStyle(.secondary)
                SettingsCard {
                    WebhookConfigurationView(model: model, configuration: settings.webhook)
                }
                SettingsCard(title: "Audio retention", symbol: "externaldrive") {
                    Text("Keep audio after delivery").font(.subheadline.weight(.medium))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 10) {
                        ForEach(choices, id: \.1) { policy, label in
                            retentionChoice(policy, label: label)
                        }
                    }
                    Text("Unsent and recovered Notes are always kept until you delete them. Timeline metadata remains after audio expires.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                SettingsCard(title: "On-device titles", symbol: "text.bubble") {
                    Toggle("Transcription", isOn: Binding(get: { settings.preferences.transcriptionEnabled }, set: { update(transcription: $0) }))
                        .accessibilityLabel("Transcription enabled")
                    Text("Only on-device recognition is used. No full transcript is stored.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Divider()
                    Text("Recognition language").font(.subheadline.weight(.medium))
                    TextField("Device language (e.g. es-ES)", text: $language)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().whimInput("Transcription language")
                    Button("Save language") { update(saveLanguage: true) }
                }
                SettingsCard(title: "Permissions", symbol: "hand.raised") {
                    permission(.microphone, status: settings.permissions.microphone, title: "Microphone")
                    Divider()
                    permission(.speech, status: settings.permissions.speech, title: "Speech recognition")
                    Divider()
                    permission(.notifications, status: settings.permissions.notifications, title: "Notifications")
                    Text("Choose whether notification previews show Note titles on the Lock Screen in system Settings → Notifications → Whim → Show Previews.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Notification preview settings") { systemSettings() }
                }
                SettingsCard(title: "Apple Watch", symbol: "applewatch") {
                    Text("Watch synchronization \(settings.watch.availability).")
                    Text("Last synchronized: \(settings.watch.lastSynchronizedAt.map(TimelineFormat.date) ?? "Not yet synchronized")")
                        .font(.footnote).foregroundStyle(.secondary)
                    if settings.watch.resetState == "pending" {
                        Text("Reset pending on Apple Watch. It will finish after reconnection.").foregroundStyle(.secondary)
                    }
                    if settings.watch.resetState == "synchronized" {
                        Text("Reset completed on both devices.").foregroundStyle(.secondary)
                    }
                    Text("A disconnected Watch cannot be erased immediately.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                SettingsCard(title: "Reset", symbol: "arrow.counterclockwise") {
                    Text("Remove all local Notes and restore Whim’s settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Reset Whim", role: .destructive) { confirm = true }
                        .foregroundStyle(.red)
                }
                if let error = model.error { WhimErrorText(message: error.message) }
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
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
    private func retentionChoice(_ policy: RetentionPolicy, label: String) -> some View {
        let selected = settings.preferences.retentionPolicy == policy
        return Button { update(retention: policy) } label: {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
                Text(label).fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 8)
            .foregroundStyle(selected ? Color.black : Color.white)
            .background(selected ? Color.white : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(selected ? 0 : 0.18), lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Keep audio: \(label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func permission(_ kind: PermissionKind, status: PermissionStatus, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title): \(status.rawValue.replacingOccurrences(of: "_", with: " "))")
            if status == .notDetermined {
                Button("Allow \(kind.rawValue)") { Task { await model.perform { _ = try await model.client.requestPermission(kind) } } }
            } else if status == .denied || status == .restricted { Button("Open \(kind.rawValue) settings") { systemSettings() } }
        }
    }
    private func systemSettings() { Task { await model.perform { try await model.client.openSystemSettings() } } }
    private func update(retention: RetentionPolicy? = nil, transcription: Bool? = nil, saveLanguage: Bool = false) {
        let locale = language.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await model.perform { try await model.client.updatePreferences(.init(retentionPolicy: retention ?? settings.preferences.retentionPolicy, transcriptionEnabled: transcription ?? settings.preferences.transcriptionEnabled, transcriptionLocaleIdentifier: saveLanguage ? (locale.isEmpty ? nil : locale) : settings.preferences.transcriptionLocaleIdentifier)) } }
    }
}

private struct SettingsCard<Content: View>: View {
    var title: String? = nil
    var symbol: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title, let symbol {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Divider()
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .whimGlass(in: RoundedRectangle(cornerRadius: 28))
    }
}
