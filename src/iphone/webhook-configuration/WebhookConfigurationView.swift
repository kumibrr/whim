import SwiftUI
import WhimCore
import WhimIPhone
struct WebhookConfigurationView: View {
    var model: IPhoneModel
    let configuration: WebhookSettingsProjection?
    @State private var editor: WebhookEditor
    @FocusState private var focused: Bool
    init(model: IPhoneModel, configuration: WebhookSettingsProjection?) {
        self.model = model; self.configuration = configuration
        _editor = State(initialValue: WebhookEditor(client: model.client))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Webhook").whimHeading().accessibilityIdentifier("webhook-configuration").onTapGesture { focused = false }
            if let configuration { Text("Current destination: \(destinationLabel(configuration.destination))").foregroundStyle(.secondary) }
            TextField(configuration == nil ? "https://your-workflow.example/whim" : "Leave blank to keep current URL", text: $editor.endpoint)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).whimInput("Webhook HTTPS URL").accessibilityIdentifier("webhook-url")
            secret("Bearer token", value: $editor.bearer, exists: configuration?.hasBearerToken == true, id: "webhook-bearer-token")
            secret("HMAC secret", value: $editor.hmac, exists: configuration?.hasHMACSecret == true, id: "webhook-hmac-secret")
            Text("Custom headers").whimHeading()
            ForEach(Array(editor.existingHeaders(configuration).enumerated()), id: \.offset) { index, header in
                VStack(alignment: .leading) {
                    Text("\(header.name) · ••••")
                    Button("Remove \(header.name)") { editor.removeHeader(at: index, configuration: configuration) }
                }
            }
            Text("Header name")
            TextField("Header name", text: $editor.newName).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).whimInput("Header name")
            Text("Header value")
            SecureField("Header value", text: $editor.newValue).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).whimInput("Header value")
            Toggle("Secret header", isOn: $editor.newSecret)
            Button("Add header") { focused = false; editor.addHeader(configuration: configuration) }
            Button("Save webhook") { focused = false; Task { await editor.save(); await model.refresh() } }
            Button("Test webhook") { focused = false; Task { await editor.test() } }.disabled(editor.isDirty)
            if editor.isDirty { Text("Save changes before testing.").foregroundStyle(.secondary) }
            if let message = editor.message { Text(message) }
            if let error = editor.error { WhimErrorText(message: error.message) }
            if editor.offersRetry { Button("Retry unsent Notes") { Task { await editor.retryUnsent(); await model.refresh() } } }
        }.disabled(editor.isPending)
    }
    private func secret(_ label: String, value: Binding<SecretPatch>, exists: Bool, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label + (exists && value.wrappedValue.action == .preserve ? " · Saved ••••" : ""))
            SecureField(exists ? "Leave blank to preserve" : "Optional", text: Binding(get: { value.wrappedValue.action == .replace ? value.wrappedValue.value ?? "" : "" }, set: { value.wrappedValue = .init(action: $0.isEmpty ? .preserve : .replace, value: $0.isEmpty ? nil : $0) }))
                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).whimInput(label).accessibilityIdentifier(id)
            if exists { Button("Clear \(label.lowercased())") { value.wrappedValue = .init(action: .clear) } }
            if value.wrappedValue.action == .clear { Text("Will be removed when saved.").foregroundStyle(.secondary) }
        }
    }
}
