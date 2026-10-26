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
                if note.audioSynchronization != nil {
                    Text("The audio has not synchronized to this iPhone.").foregroundStyle(.secondary)
                    Button {
                        Task { await model.retry(); await root.refresh() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 32, height: 32).whimGlass(in: Circle())
                            Text("Retry sync").font(.subheadline)
                        }.frame(minHeight: 48).contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Retry sync")
                        .accessibilityIdentifier("note-sync-retry")
                } else if note.requiresReview {
                    Text("Review this recovered Note, then choose Send or Delete. It will not send automatically.")
                    if note.hasLocalAudio { Button("Send Note") { Task { await model.sendRecovered(); await root.refresh() } } }
                } else if [.failed, .queued, .setupRequired].contains(note.status) {
                    Button("Retry") { Task { await model.retry(); await root.refresh() } }
                }
                Text("Delivery details").whimHeading()
                if note.attempts.isEmpty && (note.audioSynchronizationRetries ?? []).isEmpty {
                    Text("No Attempts yet.").foregroundStyle(.secondary)
                }
                ForEach(Array((note.audioSynchronizationRetries ?? []).enumerated()), id: \.element.id) { index, retry in
                    synchronizationRetryRow(retry, number: index + 1)
                }
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
                            if note.audioSynchronization == nil && note.status == .sent && !note.requiresReview { Task { await delete() } }
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
            .alert("Delete this Note?", isPresented: $confirm) {
                Button("Confirm delete", role: .destructive) { Task { await delete() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This may be the only local copy. Deleting cannot revoke delivery already accepted by your server.")
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
    private func synchronizationRetryRow(_ retry: AudioSynchronizationRetry, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sync retry \(number)").fontWeight(.medium)
                Spacer(minLength: 8)
                Text(synchronizationRetryOutcome(retry.outcome))
                    .foregroundStyle(retry.outcome == .failed ? .red : .secondary)
            }.font(.subheadline)
            Text("Apple Watch → iPhone · \(TimelineFormat.date(retry.startedAt))")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("note-sync-retry-row-\(number)")
    }
    private func synchronizationRetryOutcome(_ outcome: AudioSynchronizationRetry.Outcome) -> String {
        switch outcome {
        case .waiting: "Waiting for Watch"
        case .failed: "Failed"
        case .synced: "Synced"
        case .superseded: "Replaced by manual retry"
        }
    }
}
func destinationLabel(_ value: SanitizedEndpointProjection) -> String {
    "\(value.scheme)://\(value.host)\(value.port.map { ":\($0)" } ?? "")\(value.path)"
}
