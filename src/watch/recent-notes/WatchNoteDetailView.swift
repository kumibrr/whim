import SwiftUI
import WhimCore

struct WatchNoteDetailView: View {
    @Bindable var model: WatchModel
    let noteID: NoteID
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false
    var body: some View {
        ScrollView {
            if let note = model.notes.first(where: { $0.id == noteID }) {
                VStack {
                    Text(note.title)
                    Text(note.requiresReview ? "Review required" : note.status.watchLabel)
                    if note.hasLocalAudio {
                        if model.playback?.isPlaying == true {
                            Button("Stop Playback") { Task { await model.stopPlayback() } }
                                .accessibilityIdentifier("watch-stop-playback")
                        } else {
                            Button("Play") { Task { await model.play(note) } }
                                .accessibilityIdentifier("watch-play").disabled(model.recording != nil)
                        }
                    } else { Text("Audio unavailable") }
                    if note.status != .sent {
                        Button(note.requiresReview ? "Send" : "Retry") { Task { await model.retry(note) } }
                            .accessibilityIdentifier("watch-retry").disabled(model.isActing(on: note.id))
                    }
                    Button("Delete", role: .destructive) {
                        if note.status == .sent { Task { if await model.delete(note) { dismiss() } } }
                        else { confirmsDelete = true }
                    }.accessibilityIdentifier("watch-delete").disabled(model.isDeleting(note.id))
                    if let error = model.error { Text(error) }
                }
                .confirmationDialog("Delete this unsent Note?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                    Button("Delete Note", role: .destructive) {
                        Task { if await model.delete(note) { dismiss() } }
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await model.refreshPlayback()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .onDisappear { Task { await model.stopPlayback() } }
    }
}
