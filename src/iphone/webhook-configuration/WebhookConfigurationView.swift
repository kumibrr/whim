import SwiftUI
import WhimCore
import WhimIPhone
/// Webhook fields; the Settings header Save commits them.
struct WebhookConfigurationView: View {
    var model: IPhoneModel
    @Bindable var editor: WebhookEditor
    let configuration: WebhookSettingsProjection?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let configuration { Text("Current destination: \(destinationLabel(configuration.destination))").font(.footnote).foregroundStyle(.secondary) }
            field("Webhook URL") {
                TextField(configuration == nil ? "https://your-workflow.example/whim" : "Leave blank to keep current URL", text: $editor.endpoint)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).whimInput("Webhook HTTPS URL").accessibilityIdentifier("webhook-url")
            }
            secret("Bearer token", value: $editor.bearer, exists: configuration?.hasBearerToken == true, id: "webhook-bearer-token")
            secret("HMAC secret", value: $editor.hmac, exists: configuration?.hasHMACSecret == true, id: "webhook-hmac-secret")
            Text("Custom headers").font(.headline).accessibilityAddTraits(.isHeader).padding(.top, 8)
            ForEach(Array(editor.existingHeaders(configuration).enumerated()), id: \.offset) { index, header in
                HStack {
                    Text("\(header.name) · ••••")
                    Spacer()
                    Button("Remove", systemImage: "minus", role: .destructive) { editor.removeHeader(at: index, configuration: configuration) }
                        .labelStyle(.iconOnly).whimGlassButton().accessibilityLabel("Remove \(header.name)")
                }
            }
            if editor.isAddingHeader {
                field("Header name") {
                    TextField("X-Example", text: $editor.newName).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).whimInput("Header name")
                }
                field("Header value") {
                    SecureField("Value", text: $editor.newValue).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).whimInput("Header value")
                }
                Toggle("Secret header", isOn: $editor.newSecret)
                Button("Cancel header", role: .cancel) { editor.cancelHeader() }.whimGlassButton()
            }
            HStack(spacing: 12) {
                Button("Add header", systemImage: "plus") { focused = false; editor.addHeader(configuration: configuration) }
                    .whimGlassButton()
                Button("Test webhook", systemImage: "paperplane") { focused = false; Task { await editor.test() } }
                    .whimGlassButton().disabled(editor.isDirty)
            }
            if editor.isDirty { Text("Save changes before testing.").font(.footnote).foregroundStyle(.secondary) }
            if let message = editor.message { Text(message) }
            if let error = editor.error { WhimErrorText(message: error.message) }
            if editor.offersRetry {
                Button("Retry unsent Notes", systemImage: "arrow.clockwise") { Task { await editor.retryUnsent(); await model.refresh() } }.whimGlassButton()
            }
        }
        .disabled(editor.isPending)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("webhook-configuration")
    }
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            content()
        }
    }
    private func secret(_ label: String, value: Binding<SecretPatch>, exists: Bool, id: String) -> some View {
        field(label + (exists && value.wrappedValue.action == .preserve ? " · Saved ••••" : "")) {
            SecureField(exists ? "Leave blank to preserve" : "Optional", text: Binding(get: { value.wrappedValue.action == .replace ? value.wrappedValue.value ?? "" : "" }, set: { value.wrappedValue = .init(action: $0.isEmpty ? .preserve : .replace, value: $0.isEmpty ? nil : $0) }))
                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).whimInput(label).accessibilityIdentifier(id)
            if exists { Button("Clear \(label.lowercased())") { value.wrappedValue = .init(action: .clear) }.whimGlassButton() }
            if value.wrappedValue.action == .clear { Text("Will be removed when saved.").font(.footnote).foregroundStyle(.secondary) }
        }
    }
}
