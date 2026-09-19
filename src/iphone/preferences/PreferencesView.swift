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
        WhimContent {
            Text("Settings").whimTitle()
            WebhookConfigurationView(model: model, configuration: settings.webhook)
            Text("Keep audio after delivery").whimHeading()
            Text("Unsent and recovered Notes are always kept until you delete them. Timeline metadata remains after audio expires.").foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], alignment: .leading, spacing: 12) {
                ForEach(choices, id: \.1) { policy, label in
                    Button(label) { update(retention: policy) }.accessibilityLabel("Keep audio: \(label)")
                        .accessibilityAddTraits(settings.preferences.retentionPolicy == policy ? .isSelected : [])
                }
            }
            Text("On-device titles").whimHeading()
            Toggle("Transcription", isOn: Binding(get: { settings.preferences.transcriptionEnabled }, set: { update(transcription: $0) })).accessibilityLabel("Transcription enabled")
            Text("Only on-device recognition is used. No full transcript is stored.").foregroundStyle(.secondary)
            TextField("Device language (e.g. es-ES)", text: $language).textInputAutocapitalization(.never).autocorrectionDisabled().whimInput("Transcription language")
            Button("Save language") { update(saveLanguage: true) }
            Text("Permissions").whimHeading()
            permission(.microphone, status: settings.permissions.microphone, title: "Microphone")
            permission(.speech, status: settings.permissions.speech, title: "Speech recognition")
            permission(.notifications, status: settings.permissions.notifications, title: "Notifications")
            Text("Choose whether notification previews show Note titles on the Lock Screen in system Settings → Notifications → Whim → Show Previews.").foregroundStyle(.secondary)
            Button("Notification preview settings") { systemSettings() }
            Text("Apple Watch").whimHeading()
            Text("Watch synchronization \(settings.watch.availability).").foregroundStyle(.secondary)
            Text("Last synchronized: \(settings.watch.lastSynchronizedAt.map(TimelineFormat.date) ?? "Not yet synchronized")").foregroundStyle(.secondary)
            if settings.watch.resetState == "pending" { Text("Reset pending on Apple Watch. It will finish after reconnection.").foregroundStyle(.secondary) }
            if settings.watch.resetState == "synchronized" { Text("Reset completed on both devices.").foregroundStyle(.secondary) }
            Text("A disconnected Watch cannot be erased immediately.").foregroundStyle(.secondary)
            if let error = model.error { WhimErrorText(message: error.message) }
            Button("Reset Whim", role: .destructive) { confirm = true }
        }.disabled(model.isPending).accessibilityIdentifier("preferences").navigationTitle("Whim").toolbar(.visible, for: .navigationBar)
            .sheet(isPresented: $confirm) {
                ConfirmationView(title: "Reset Whim on this iPhone?", message: "This removes all local audio, Notes, history, webhook configuration and credentials. It cannot revoke delivery accepted by your server or erase a disconnected Watch immediately.", confirm: "Confirm reset", error: model.error?.message, onCancel: { confirm = false }, onConfirm: { await model.perform { try await model.client.reset() } })
                    .presentationDetents([.medium, .large]).interactiveDismissDisabled(model.isPending)
            }
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
