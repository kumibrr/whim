import SwiftUI
import WhimCore

struct WatchRecentNotesView: View {
    @Bindable var model: WatchModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if let error = model.error {
                Text(error).accessibilityIdentifier("watch-notes-error")
                Button("Refresh Notes") { Task { await model.refreshNotes() } }
                    .accessibilityIdentifier("watch-refresh-notes")
            }

            if model.notes.isEmpty {
                Text("No Notes yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(model.notes, id: \.id) { note in
                NavigationLink {
                    WatchNoteDetailView(model: model, noteID: note.id)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.title).lineLimit(1)
                        Text(note.requiresReview ? "Review required" : note.status.watchLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watch-note-\(note.id.rawValue.uuidString.lowercased())")
            }
        }
    }
}

extension DeliveryStatus {
    var watchLabel: String {
        switch self {
        case .setupRequired: "Setup required"
        case .queued: "Queued"
        case .sending: "Sending"
        case .sent: "Sent"
        case .failed: "Failed"
        }
    }
}
