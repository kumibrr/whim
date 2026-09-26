import SwiftUI
import WhimCore
import WhimIPhone

struct TimelineView: View {
    var model: IPhoneModel
    var open: (NoteID) -> Void
    @State private var filter = "All"
    private var visible: [NoteProjection] {
        model.notes.filter { note in
            filter == "All"
                || (filter == "Queued"
                    ? [.queued, .setupRequired, .sending].contains(note.status)
                    : note.status.rawValue == filter.lowercased())
        }
    }
    var body: some View {
        WhimContent {
            ViewThatFits(in: .horizontal) {
                HStack { filters }
                VStack(alignment: .leading) { filters }
            }
            if filter == "Failed" && visible.contains(where: { !$0.requiresReview }) {
                Button("Retry all failed Notes") {
                    Task { await model.perform { _ = try await model.client.retryAllFailed() } }
                }
            }
            if visible.isEmpty {
                if model.historyError != nil {
                    Text("History is unavailable. Retry loading your saved Notes.").foregroundStyle(.secondary)
                } else {
                    Text("No Notes here yet. Capture a thought.").foregroundStyle(.secondary)
                }
            }
            LazyVStack(spacing: 14) {
                ForEach(visible, id: \.id) { note in
                    NoteRowView(
                        note: note, waveform: model.waveforms[note.id], playback: model.playback,
                        playbackFailure: model.playbackFailure(for: note.id),
                        open: { open(note.id) },
                        retry: {
                            Task {
                                await model.perform {
                                    try await model.client.retry(noteID: note.id)
                                }
                            }
                        },
                        togglePlayback: {
                            Task {
                                if model.playback?.noteID
                                    == note.id.rawValue.uuidString.lowercased(),
                                    model.playback?.isPlaying == true
                                {
                                    await model.stopInlinePlayback()
                                } else {
                                    await model.playInline(note.id)
                                }
                            }
                        }
                    )
                    .task(id: note.hasLocalAudio) { await model.loadWaveform(note.id) }
                }
            }
        }.accessibilityIdentifier("notes-list")
    }
    private var filters: some View {
        ForEach(["All", "Queued", "Failed", "Sent"], id: \.self) { value in
            Button {
                filter = value
            } label: {
                Text(value).font(.system(.caption, weight: .medium)).padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(filter == value ? .black : .white.opacity(0.65))
                    .background(
                        filter == value ? Color.white : Color.white.opacity(0.06), in: Capsule()
                    )
                    .frame(minHeight: 48)
            }.buttonStyle(.plain).accessibilityLabel("\(value) filter").accessibilityAddTraits(
                filter == value ? .isSelected : [])
        }
    }
}

/// The system owns the sheet's interactive transition and scroll coordination.
struct HistorySheet: View {
    var model: IPhoneModel
    @State private var path: [NoteID] = []
    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(model: model) { id in
                Task { if await model.prepareForNavigation() { path.append(id) } }
            }
            .navigationTitle("Previous notes")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await model.closeHistory() }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.automatic)
                    .accessibilityLabel("Close history")
                    .accessibilityIdentifier("history-close")
                }
            }
            .navigationDestination(for: NoteID.self) { id in
                NoteDetailView(root: model, noteID: id)
            }
        }
        .accessibilityIdentifier("history-sheet")
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
    }
}
