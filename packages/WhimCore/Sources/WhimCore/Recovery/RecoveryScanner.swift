import Foundation

/// Call at cold startup after the recording adapter has established that no writer is active.
public struct RecoveryScanner: Sendable {
    private let store: any WhimStore
    private let files: any AudioFileManaging
    private let source: CaptureSource

    public init(store: any WhimStore, files: any AudioFileManaging, source: CaptureSource = .iphone) {
        self.store = store
        self.files = files
        self.source = source
    }

    public func scan() async throws {
        for deletion in try await store.deletions() {
            try files.delete(noteID: deletion.noteID)
            if let sessionID = deletion.recordingSessionID { try files.deleteTemporary(sessionID: sessionID) }
        }
        for row in try await store.listNotes(filter: .all) {
            guard let note = try await store.note(id: row.id), note.localError == nil else { continue }
            if let error = files.audioError(at: note.audioURL) {
                try await store.recordLocalError(error, noteID: note.id)
            }
        }
        let sessions = try await store.recordingSessions()
        for noteID in try files.durableNoteIDs() {
            guard try await store.note(id: noteID) == nil else { continue }
            let existingSession = sessions.first { $0.noteID == noteID }
            let audio: FinalizedAudio
            do {
                guard let durableAudio = try files.durableAudio(noteID: noteID) else {
                    try await saveDurableRecoveryError(noteID: noteID, session: existingSession)
                    continue
                }
                audio = durableAudio
            } catch {
                try await saveDurableRecoveryError(noteID: noteID, session: existingSession)
                continue
            }
            let session = existingSession ?? RecordingSession(
                id: RecordingSessionID(rawValue: noteID.rawValue), noteID: noteID, createdAt: audio.createdAt, source: source)
            _ = try await store.saveFinalized(FinalizedRecording(id: noteID, recordingSessionID: session.id,
                title: "Recovered recording", titleSource: .recovered, createdAt: session.createdAt,
                duration: audio.duration, source: session.source, captureOutcome: .recovered, requiresReview: true, audioURL: audio.url))
        }
        for session in try await store.recordingSessions() {
            do {
                guard try files.playablePartial(sessionID: session.id) != nil else {
                    let url = try files.temporaryURL(for: session.id)
                    try await saveRecoveryError(session: session, url: url, error: files.audioError(at: url) ?? .unreadable)
                    continue
                }
            } catch {
                try await saveRecoveryError(session: session, url: files.temporaryURL(for: session.id), error: .unreadable)
                continue
            }
            let audio = try files.finalize(sessionID: session.id, noteID: session.noteID)
            _ = try await store.saveFinalized(FinalizedRecording(id: session.noteID, recordingSessionID: session.id,
                title: "Recovered recording", titleSource: .recovered, createdAt: session.createdAt,
                duration: audio.duration, source: session.source, captureOutcome: .recovered, requiresReview: true, audioURL: audio.url))
        }
    }

    private func saveDurableRecoveryError(noteID: NoteID, session: RecordingSession?) async throws {
        let url = files.audioURL(for: noteID)
        let recoveredSession = session ?? RecordingSession(
            id: RecordingSessionID(rawValue: noteID.rawValue), noteID: noteID, createdAt: Date(), source: source)
        try await saveRecoveryError(
            session: recoveredSession,
            url: url,
            error: files.audioError(at: url) ?? .durabilityFailure
        )
    }

    private func saveRecoveryError(session: RecordingSession, url: URL, error: LocalAudioError) async throws {
        try await store.saveRecoveryError(FinalizedRecording(id: session.noteID, recordingSessionID: session.id,
            title: "Recovered recording", titleSource: .recovered, createdAt: session.createdAt,
            duration: 0, source: session.source, captureOutcome: .recovered, requiresReview: true,
            audioURL: url), error: error)
    }
}
