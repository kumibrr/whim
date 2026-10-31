import SwiftUI
import WhimCore
import WhimIPhone

struct TimelineView: View {
    var model: IPhoneModel
    var open: (NoteID) -> Void
    @State private var filter = "All"
    private var visible: [NoteProjection] {
        model.notes.filter { note in
            guard let selected = NoteFilter(rawValue: filter.lowercased()) else { return true }
            return note.matches(selected)
                || (selected == .queued && [.queued, .setupRequired, .sending].contains(note.status))
        }
    }
    var body: some View {
        WhimContent {
            ViewThatFits(in: .horizontal) {
                HStack { filters }
                VStack(alignment: .leading) { filters }
            }
            if filter == "Failed" && visible.contains(where: { !$0.requiresReview && $0.audioSynchronization == nil }) {
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
            LazyVStack(spacing: WhimSpacing.group) {
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
                Text(value).font(.system(.caption, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .whimGlass(in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(filter == value ? 0.8 : 0), lineWidth: 1.5))
                    .frame(minHeight: 44).contentShape(Rectangle())
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
