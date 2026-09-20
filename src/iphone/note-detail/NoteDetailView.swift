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
                NoteRowView(
                    note: note, waveform: model.waveform, playback: model.playback,
                    open: nil, retry: nil,
                    togglePlayback: {
                        Task { if model.isPlaying { await model.stopPlayback() } else { await model.play() } }
                    }
                )
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
            } else {
                Text("This Note is unavailable.")
                Button("Return to timeline") { dismiss() }
            }
            if let error = model.error, error.recovery.operation != .playback { WhimErrorText(message: error.message) }
        }.accessibilityIdentifier("note-detail").disabled(model.isPending).navigationTitle("").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                if let failure = model.error?.recovery, failure.operation == .playback {
                    WhimErrorContainer(message: failure.message, actionLabel: failure.actionLabel, busy: model.isPending) {
                        Task { await model.play() }
                    }.padding(.horizontal, 20)
                }
            }
            .toolbar {
                if let note = model.note {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if note.status == .sent && !note.requiresReview { Task { await delete() } }
                            else { confirm = true }
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.automatic)
                        .tint(.red)
                        .accessibilityLabel("Delete Note")
                        .accessibilityIdentifier("note-delete")
                        .disabled(model.isPending)
                    }
                }
            }
            .sheet(isPresented: $confirm) {
                ConfirmationView(title: "Delete this Note?", message: "This may be the only local copy. Deleting cannot revoke delivery already accepted by your server.", confirm: "Confirm delete", error: model.error?.message, onCancel: { confirm = false }, onConfirm: delete)
                    .presentationDetents([.medium, .large]).interactiveDismissDisabled(model.isPending)
            }
            .task(id: model.note?.hasLocalAudio) { await model.loadWaveform() }
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
