import SwiftUI
import WhimCore
import WhimIPhone
struct NoteDetailView: View {
    var root: IPhoneModel
    @State private var model: NoteDetailModel
    @State private var confirm = false
    @Environment(\.dismiss) private var dismiss
    init(root: IPhoneModel, noteID: NoteID) {
        self.root = root; _model = State(initialValue: NoteDetailModel(client: root.client, noteID: noteID))
    }
    var body: some View {
        WhimContent {
            if let note = model.note {
                Text(note.title).whimTitle()
                Text(TimelineFormat.date(note.createdAt)).foregroundStyle(.secondary)
                Text("\(TimelineFormat.source(note.source)) · \(TimelineFormat.duration(seconds: note.durationSeconds))")
                Text(note.requiresReview ? "Review required" : TimelineFormat.status(note.status)).whimHeading().foregroundStyle(note.status == .failed ? Color.red : .primary)
                if note.hasLocalAudio {
                    Button(model.isPlaying ? "Stop playback" : note.requiresReview ? "Review recording" : "Play Note") {
                        Task { if model.isPlaying { await model.stopPlayback() } else { await model.play() } }
                    }
                } else { Text(note.localError == nil ? "Audio expired" : "Audio unavailable").foregroundStyle(.secondary) }
                if model.isPlaying { Text("Playing") }
                if let error = note.localError { Text("Local audio error: \(error.rawValue)").foregroundStyle(.red) }
                if note.workflowError != nil { Text("Delivery could not continue. Your Note is preserved.").foregroundStyle(.red) }
                if note.requiresReview {
                    Text("Review this recovered Note, then choose Send or Delete. It will not send automatically.")
                    if note.hasLocalAudio { Button("Send Note") { Task { await model.sendRecovered(); await root.refresh() } } }
                } else if [.failed, .queued, .setupRequired].contains(note.status) {
                    Button("Retry") { Task { await model.retry(); await root.refresh() } }
                }
                Text("Delivery details").whimHeading()
                if note.attempts.isEmpty { Text("No Attempts yet.").foregroundStyle(.secondary) }
                ForEach(note.attempts, id: \.id) { attempt in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(attempt.outcome == .sent ? "✓ Sent" : attempt.outcome == .failed ? "⚠ Failed" : "Sending")\(attempt.responseStatusCode.map { " · HTTP \($0)" } ?? "")")
                        Text(destinationLabel(attempt.destination)).foregroundStyle(.secondary)
                        Text("\(TimelineFormat.date(attempt.startedAt)) · \(TimelineFormat.source(attempt.device))").foregroundStyle(.secondary)
                        if let reason = attempt.failureReason { Text(reason == "network" ? "The destination could not be reached." : "The destination rejected this Attempt.").foregroundStyle(.red) }
                        Text("Configuration Revision: \(attempt.configurationRevisionID)").foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Button("Delete Note") {
                    if note.status == .sent && !note.requiresReview { Task { await delete() } }
                    else { confirm = true }
                }
            } else {
                Text("This Note is unavailable.")
                Button("Return to timeline") { dismiss() }
            }
            if let error = model.error { WhimErrorText(message: error.message) }
        }.accessibilityIdentifier("note-detail").disabled(model.isPending).navigationTitle("Whim").toolbar(.visible, for: .navigationBar)
            .sheet(isPresented: $confirm) {
                ConfirmationView(title: "Delete this Note?", message: "This may be the only local copy. Deleting cannot revoke delivery already accepted by your server.", confirm: "Confirm delete", error: model.error?.message, onCancel: { confirm = false }, onConfirm: delete)
                    .presentationDetents([.medium, .large]).interactiveDismissDisabled(model.isPending)
            }
            .task(id: root.revision) { await model.refresh() }
            .task {
                while !Task.isCancelled {
                    await model.refresh()
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
                }
            }
            .onDisappear { Task { await model.stopPlayback() } }
    }
    private func delete() async {
        await model.delete()
        if model.deleted { confirm = false; await root.refresh(); dismiss() }
    }
}
func destinationLabel(_ value: SanitizedEndpointProjection) -> String {
    "\(value.scheme)://\(value.host)\(value.port.map { ":\($0)" } ?? "")\(value.path)"
}
