import SwiftUI
struct ConfirmationView: View {
    let title: String
    let message: String
    let confirm: String
    var cancel = "Cancel"
    var error: String? = nil
    let onCancel: () -> Void
    let onConfirm: () async -> Void
    @State private var pending = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).whimHeading()
            Text(message)
            Button(confirm, role: .destructive) {
                guard !pending else { return }; pending = true
                Task { await onConfirm(); pending = false }
            }
            Button(cancel, action: onCancel)
            if let error { Text(error).foregroundStyle(.red) }
        }.padding(24).background(Color(uiColor: .secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 14)).disabled(pending)
    }
}
