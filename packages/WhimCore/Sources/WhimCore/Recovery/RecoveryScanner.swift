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

    public struct Inventory: Sendable {
        let deletions: [DeletionTombstone]
        let notes: [NoteID]
        let durable: [NoteID]
        let sessions: [RecordingSession]
    }

    /// Metadata only. Freeze the candidate set before admitting new capture.
    public func inventory() async throws -> Inventory {
        let deletions = try await store.deletions()
        let sessions = try await store.recordingSessions()
        let notes = try await store.listNotes(filter: .all).map(\.id)
        return try Inventory(deletions: deletions, notes: notes,
            durable: files.durableNoteIDs(), sessions: sessions)
    }

    public func scan() async throws { try await scan(inventory()) }

    public func scan(_ inventory: Inventory) async throws {
        for deletion in inventory.deletions {
            try Task.checkCancellation()
            guard let ownership = try files.claimOwnership(noteID: deletion.noteID) else { continue }
            defer { withExtendedLifetime(ownership) {} }
            try files.delete(noteID: deletion.noteID)
            if let sessionID = deletion.recordingSessionID { try files.deleteTemporary(sessionID: sessionID) }
        }
        for id in inventory.notes {
            try Task.checkCancellation()
            guard let ownership = try files.claimOwnership(noteID: id) else { continue }
            defer { withExtendedLifetime(ownership) {} }
            guard let note = try await store.note(id: id), note.localError == nil else { continue }
            if note.audioExpiredAt != nil {
                try files.delete(noteID: id)
                continue
            }
            if let error = files.audioError(at: note.audioURL) {
                try await store.recordLocalError(error, noteID: note.id)
            }
        }
        let deleted = Set(try await store.deletions().map(\.noteID))
        for noteID in inventory.durable where !deleted.contains(noteID) {
            try Task.checkCancellation()
            guard let ownership = try files.claimOwnership(noteID: noteID) else { continue }
            defer { withExtendedLifetime(ownership) {} }
            guard try await store.note(id: noteID) == nil else { continue }
            let existingSession = inventory.sessions.first { $0.noteID == noteID }
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
        for session in inventory.sessions where !deleted.contains(session.noteID) {
            try Task.checkCancellation()
            guard let ownership = try files.claimOwnership(noteID: session.noteID) else { continue }
            defer { withExtendedLifetime(ownership) {} }
            // Another recovery or a live writer may have finalized since inventory creation.
            guard try await store.note(id: session.noteID) == nil,
                  try await store.recordingSessions().contains(where: { $0.id == session.id }) else { continue }
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
