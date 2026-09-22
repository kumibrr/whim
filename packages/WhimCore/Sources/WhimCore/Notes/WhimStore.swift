import Foundation

public enum LeaseKind: String, Codable, Sendable {
    case delivery
    case titleEnrichment = "title_enrichment"
}

public protocol WhimStore: Sendable {
    /// Persist intentional expiry before unlinking audio; never expires an unsent Note.
    func markAudioExpired(noteID: NoteID, at date: Date) async throws -> Bool
    func latestConfigurationRevision() async throws -> ConfigurationRevision?
    func reset() async throws
    func recordLocalError(_ error: LocalAudioError, noteID: NoteID) async throws
    func saveRecoveryError(_ recording: FinalizedRecording, error: LocalAudioError) async throws
    func send(noteID: NoteID) async throws
    func saveRecordingSession(_ session: RecordingSession) async throws
    func recordingSessions() async throws -> [RecordingSession]
    func discardRecordingSession(sessionID: RecordingSessionID) async throws
    func recordSessionError(_ error: LocalAudioError, sessionID: RecordingSessionID) async throws
    /// Persist deletion before removing audio, so recovery cannot resurrect a remaining file.
    func delete(noteID: NoteID) async throws
    func acknowledgeDeletion(noteID: NoteID, endpoint: AttemptDevice) async throws
    func deletions() async throws -> [DeletionTombstone]
    func saveConfigurationRevision(_ revision: ConfigurationRevision) async throws
    func configurationRevision(for noteID: NoteID) async throws -> ConfigurationRevision?
    func note(id: NoteID) async throws -> Note?
    func deliveryAttempts(noteID: NoteID) async throws -> [Attempt]
    func listNotes(filter: NoteFilter) async throws -> [NoteProjection]
    func saveFinalized(_ finalized: FinalizedRecording) async throws -> Note
    func updateTitle(noteID: NoteID, title: String, source: TitleSource) async throws
    func apply(_ event: DeliveryEvent, to noteID: NoteID) async throws -> Delivery
    func acquireLease(
        _ kind: LeaseKind,
        noteID: NoteID,
        owner: UUID,
        until: Date
    ) async throws -> Bool
    func releaseLease(_ kind: LeaseKind, noteID: NoteID, owner: UUID) async throws
    func beginRetryCycle(noteID: NoteID) async throws -> Bool
    func markExhaustionNotified(noteID: NoteID, retryCycle: Int) async throws -> Bool
}

public extension WhimStore {
    func markAudioExpired(noteID: NoteID, at date: Date) async throws -> Bool { throw WhimStoreError.unsupportedOperation }
    func latestConfigurationRevision() async throws -> ConfigurationRevision? { nil }
    func reset() async throws { throw WhimStoreError.unsupportedOperation }
    func deliveryAttempts(noteID: NoteID) async throws -> [Attempt] {
        guard let note = try await note(id: noteID) else { return [] }
        let values = note.delivery.activeAttempts + note.delivery.failedAttempts.map(\.attempt)
        var seen = Set<AttemptID>()
        return values.filter { seen.insert($0.id).inserted }
    }
    func beginRetryCycle(noteID: NoteID) async throws -> Bool { false }
    func markExhaustionNotified(noteID: NoteID, retryCycle: Int) async throws -> Bool { true }
}

public enum LocalAudioError: String, Codable, Sendable {
    case storageFull, unreadable, missing, durabilityFailure
}

public struct RecordingSession: Codable, Equatable, Sendable {
    public let id: RecordingSessionID
    public let noteID: NoteID
    public let createdAt: Date
    public let source: CaptureSource
    public internal(set) var localError: LocalAudioError?

    public init(id: RecordingSessionID, noteID: NoteID, createdAt: Date, source: CaptureSource) {
        self.id = id
        self.noteID = noteID
        self.createdAt = createdAt
        self.source = source
    }
}

public struct DeletionTombstone: Equatable, Sendable {
    public let noteID: NoteID
    public let recordingSessionID: RecordingSessionID?
    public let acknowledgedEndpoints: [AttemptDevice]
}

/// Non-secret revision facts. Full configuration and credentials belong to the configuration/Keychain adapter.
public struct ConfigurationRevision: Codable, Equatable, Sendable {
    public let id: ConfigurationRevisionID
    public let changedAt: Date
    public let endpoint: SanitizedEndpoint

    public init(id: ConfigurationRevisionID, changedAt: Date, endpoint: SanitizedEndpoint) {
        self.id = id
        self.changedAt = changedAt
        self.endpoint = endpoint
    }
}
