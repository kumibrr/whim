import SwiftUI
import WhimCore

struct WatchRecentNotesView: View {
    @Bindable var model: WatchModel
    @State private var showsSettled = false

    var body: some View {
        let sections = model.sections
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

            ForEach(sections.active, id: \.id) { row($0) }

            Button {
                Task { await model.syncNow() }
            } label: {
                Label(model.isSyncing ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .disabled(model.isSyncing)
            .accessibilityIdentifier("watch-sync-now")
            if let status = model.syncStatus {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("watch-sync-status")
            }

            if !sections.settled.isEmpty {
                // watchOS has no DisclosureGroup; a toggle row reveals the settled Notes.
                Button {
                    withAnimation { showsSettled.toggle() }
                } label: {
                    HStack {
                        Text("Settled (\(sections.settled.count))")
                        Spacer()
                        Image(systemName: showsSettled ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsSettled ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("watch-settled")
                if showsSettled {
                    ForEach(sections.settled, id: \.id) { row($0) }
                }
            }
        }
    }

    private func row(_ note: NoteProjection) -> some View {
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
