import SwiftUI
import WhimCore
import WhimIPhone
/// Onboarding saves on blur; Settings uses its header Save action.
struct WebhookConfigurationView: View {
    var model: IPhoneModel
    @Bindable var editor: WebhookEditor
    let configuration: WebhookSettingsProjection?
    var compact = false
    @State private var showsAdvancedOptions = false
    private enum Field: Hashable { case endpoint, bearer, hmac, headerName, headerValue }
    @FocusState private var focused: Field?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let configuration, editor.endpoint.isEmpty { Text("Current destination: \(destinationLabel(configuration.destination))").font(.footnote).foregroundStyle(.secondary) }
            field("Webhook URL") {
                TextField(configuration == nil ? "https://your-workflow.example/whim" : "Leave blank to keep current URL", text: $editor.endpoint)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .endpoint).whimInput("Webhook HTTPS URL").accessibilityIdentifier("webhook-url")
            }
            if compact {
                DisclosureGroup("Authentication & headers", isExpanded: $showsAdvancedOptions) {
                    advancedFields.padding(.top, 12)
                    addHeaderButton.padding(.top, 12)
                }.font(.subheadline)
            } else {
                advancedFields
            }
            HStack(spacing: 12) {
                if !compact { addHeaderButton }
                Button("Test webhook", systemImage: "paperplane") {
                    focused = nil
                    Task { await editor.test(saveChanges: compact); await model.refresh() }
                }
                    .whimGlassButton().disabled(!compact && editor.isDirty)
            }
            if compact { Text("Changes save automatically when you leave a field.").font(.footnote).foregroundStyle(.secondary) }
            else if editor.isDirty { Text("Save changes before testing.").font(.footnote).foregroundStyle(.secondary) }
            if let message = editor.message { Text(message) }
            if let error = editor.error { WhimErrorText(message: error.message) }
            if !compact && editor.offersRetry {
                Button("Retry unsent Notes", systemImage: "arrow.clockwise") { Task { await editor.retryUnsent(); await model.refresh() } }.whimGlassButton()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
                    .accessibilityIdentifier("webhook-keyboard-done")
            }
        }
        .onChange(of: focused) { previous, _ in
            if previous != nil { saveOnBlur() }
        }
        .disabled(editor.isPending)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("webhook-configuration")
    }
    private var advancedFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            secret("Bearer token", value: $editor.bearer, exists: configuration?.hasBearerToken == true, id: "webhook-bearer-token", focus: .bearer)
            secret("HMAC secret", value: $editor.hmac, exists: configuration?.hasHMACSecret == true, id: "webhook-hmac-secret", focus: .hmac)
            Text("Custom headers").font(.headline).accessibilityAddTraits(.isHeader).padding(.top, 8)
            ForEach(Array(editor.existingHeaders(configuration).enumerated()), id: \.offset) { index, header in
                HStack {
                    Text("\(header.name) · ••••")
                    Spacer()
                    Button("Remove", systemImage: "minus", role: .destructive) { editor.removeHeader(at: index, configuration: configuration); saveOnBlur() }
                        .labelStyle(.iconOnly).whimGlassButton().accessibilityLabel("Remove \(header.name)")
                }
            }
            if editor.isAddingHeader {
                field("Header name") {
                    TextField("X-Example", text: $editor.newName).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .headerName).whimInput("Header name")
                }
                field("Header value") {
                    SecureField("Value", text: $editor.newValue).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .headerValue).whimInput("Header value")
                }
                Toggle("Secret header", isOn: $editor.newSecret)
                Button("Cancel header", role: .cancel) { editor.cancelHeader(); saveOnBlur() }.whimGlassButton()
            }
        }
    }
    private var addHeaderButton: some View {
        Button("Add header", systemImage: "plus") {
            focused = nil
            if compact {
                Task {
                    await editor.saveIfNeeded(); await model.refresh()
                    if editor.error == nil { editor.addHeader(configuration: model.settings?.webhook ?? configuration) }
                }
            } else { editor.addHeader(configuration: configuration) }
        }
            .whimGlassButton()
    }
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            content()
        }
    }
    private func secret(_ label: String, value: Binding<SecretPatch>, exists: Bool, id: String, focus: Field) -> some View {
        field(label + (exists && value.wrappedValue.action == .preserve ? " · Saved ••••" : "")) {
            SecureField(exists ? "Leave blank to preserve" : "Optional", text: Binding(get: { value.wrappedValue.action == .replace ? value.wrappedValue.value ?? "" : "" }, set: { value.wrappedValue = .init(action: $0.isEmpty ? .preserve : .replace, value: $0.isEmpty ? nil : $0) }))
                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: focus).whimInput(label).accessibilityIdentifier(id)
            if exists { Button("Clear \(label.lowercased())") { value.wrappedValue = .init(action: .clear); saveOnBlur() }.whimGlassButton() }
            if value.wrappedValue.action == .clear { Text("Will be removed when saved.").font(.footnote).foregroundStyle(.secondary) }
        }
    }
    private func saveOnBlur() {
        guard compact else { return }
        // Keep a partially entered header editable until its name and value are ready.
        guard !editor.isAddingHeader || (!editor.newName.isEmpty && !editor.newValue.isEmpty) else { return }
        Task { await editor.saveIfNeeded(); await model.refresh() }
    }
}
