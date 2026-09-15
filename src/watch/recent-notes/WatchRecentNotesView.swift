import SwiftUI
import WhimCore

struct WatchRecentNotesView: View {
    @Bindable var model: WatchModel
    var body: some View {
        List {
            if model.notes.isEmpty { Text("No Notes yet") }
            ForEach(model.notes, id: \.id) { note in
                NavigationLink {
                    WatchNoteDetailView(model: model, noteID: note.id)
                } label: {
                    VStack(alignment: .leading) {
                        Text(note.title)
                        Text(note.requiresReview ? "Review required" : note.status.watchLabel).font(.caption)
                    }
                }
                .accessibilityIdentifier("watch-note-\(note.id.rawValue.uuidString.lowercased())")
            }
        }
        .navigationTitle("Recent Notes")
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
