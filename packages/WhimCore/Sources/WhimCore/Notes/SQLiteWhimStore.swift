import Foundation
import GRDB

public enum WhimStoreError: Error { case missingNote, deletedNote, notEligible, invalidEvent, unsupportedOperation }

public actor SQLiteWhimStore: WhimStore {
    private let database: DatabaseQueue
    private let now: @Sendable () -> Date
    private var isConnected = true

    private init(database: DatabaseQueue, now: @escaping @Sendable () -> Date) {
        self.database = database
        self.now = now
    }

    public static func open(at url: URL, now: @escaping @Sendable () -> Date = { Date() }) throws -> SQLiteWhimStore {
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        try WhimDatabaseMigrator.migrate(queue)
        return SQLiteWhimStore(database: queue, now: now)
    }

    public func note(id: NoteID) async throws -> Note? {
        let time = now(), connected = isConnected
        return try await database.read { db in try Self.readNote(id: id, db: db, time: time, connected: connected) }
    }

    private static func readNote(id: NoteID, db: Database, time: Date = Date(), connected: Bool = true) throws -> Note? {
        guard let data = try Data.fetchOne(db, sql: "SELECT metadata FROM notes WHERE id = ?", arguments: [id.rawValue.uuidString]) else { return nil }
        let recording = try JSONDecoder().decode(FinalizedRecording.self, from: data)
        let retryCycle = try Int.fetchOne(db, sql: "SELECT retry_cycle FROM deliveries WHERE note_id = ?",
            arguments: [id.rawValue.uuidString]) ?? 0
        let workflowError = try String.fetchOne(db,
            sql: "SELECT workflow_error FROM deliveries WHERE note_id = ?",
            arguments: [id.rawValue.uuidString]).flatMap(DeliveryWorkflowError.init(rawValue:))
        var delivery = Delivery(hasUsableConfiguration: try Self.latestRevision(db: db) != nil,
            currentRetryCycle: retryCycle, workflowError: workflowError)
        delivery.isConnected = connected
        delivery.hasExecutionLease = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM leases WHERE note_id = ? AND kind = 'delivery' AND expires_at > ?)", arguments: [id.rawValue.uuidString, time.timeIntervalSince1970]) == true
        for row in try Row.fetchAll(db, sql: "SELECT metadata, failure FROM attempts WHERE note_id = ? ORDER BY rowid", arguments: [id.rawValue.uuidString]) {
            guard let metadata: Data = row["metadata"] else { continue }
            if let failure: Data = row["failure"] {
                delivery = DeliveryReducer.reduce(delivery, event: .attemptFailed(try JSONDecoder().decode(AttemptFailure.self, from: failure)))
            } else {
                delivery = DeliveryReducer.reduce(delivery, event: .attemptStarted(try JSONDecoder().decode(Attempt.self, from: metadata)))
            }
        }
        for receipt in try Data.fetchAll(db, sql: "SELECT metadata FROM receipts WHERE note_id = ? ORDER BY rowid", arguments: [id.rawValue.uuidString]) {
            delivery = DeliveryReducer.reduce(delivery, event: .receipt(try JSONDecoder().decode(Receipt.self, from: receipt)))
        }
        return Note(id: recording.id, recordingSessionID: recording.recordingSessionID,
            title: recording.title, titleSource: recording.titleSource, createdAt: recording.createdAt,
            duration: recording.duration, source: recording.source, captureOutcome: recording.captureOutcome,
            requiresReview: recording.requiresReview, audioURL: recording.audioURL, delivery: delivery,
            localError: try String.fetchOne(db, sql: "SELECT local_error FROM notes WHERE id = ?", arguments: [id.rawValue.uuidString]).flatMap(LocalAudioError.init(rawValue:)))
    }

    public func saveFinalized(_ finalized: FinalizedRecording) async throws -> Note {
        try await database.write { db in
            try Self.insertFinalized(finalized, db: db)
        }
    }

    private static func insertFinalized(_ finalized: FinalizedRecording, db: Database) throws -> Note {
        guard try !Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM tombstones WHERE note_id = ?)", arguments: [finalized.id.rawValue.uuidString])! else { throw WhimStoreError.deletedNote }
        if let existing = try Self.readNote(id: finalized.id, db: db) { return existing }
        try db.execute(sql: "INSERT INTO notes (id, session_id, created_at, metadata) VALUES (?, ?, ?, ?)", arguments: [
            finalized.id.rawValue.uuidString, finalized.recordingSessionID.rawValue.uuidString,
            finalized.createdAt.timeIntervalSince1970, try JSONEncoder().encode(finalized),
        ])
        try db.execute(sql: "INSERT INTO deliveries (note_id) VALUES (?)", arguments: [finalized.id.rawValue.uuidString])
        for step in WorkflowDefinition.default.steps {
            try db.execute(sql: "INSERT INTO workflow_steps (note_id, step_id) VALUES (?, ?)", arguments: [finalized.id.rawValue.uuidString, step.id])
        }
        try db.execute(sql: "DELETE FROM recording_sessions WHERE id = ?", arguments: [finalized.recordingSessionID.rawValue.uuidString])
        return try Self.readNote(id: finalized.id, db: db)!
    }

    public func saveRecoveryError(_ recording: FinalizedRecording, error: LocalAudioError) async throws {
        try await database.write { db in
            _ = try Self.insertFinalized(recording, db: db)
            try db.execute(sql: "UPDATE notes SET local_error = ? WHERE id = ?", arguments: [error.rawValue, recording.id.rawValue.uuidString])
        }
    }

    public func recordLocalError(_ error: LocalAudioError, noteID: NoteID) async throws {
        try await database.write { db in
            try db.execute(sql: "UPDATE notes SET local_error = ? WHERE id = ?", arguments: [error.rawValue, noteID.rawValue.uuidString])
        }
    }

    public func delete(noteID: NoteID) async throws {
        try await database.write { db in
            let sessionID = try String.fetchOne(db, sql: "SELECT session_id FROM notes WHERE id = ?", arguments: [noteID.rawValue.uuidString])
            try db.execute(sql: "INSERT OR IGNORE INTO tombstones (note_id, session_id) VALUES (?, ?)", arguments: [noteID.rawValue.uuidString, sessionID])
            try db.execute(sql: "DELETE FROM notes WHERE id = ?", arguments: [noteID.rawValue.uuidString])
        }
    }

    public func saveRecordingSession(_ session: RecordingSession) async throws {
        try await database.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO recording_sessions (id, metadata) VALUES (?, ?)", arguments: [session.id.rawValue.uuidString, try JSONEncoder().encode(session)])
        }
    }

    public func recordingSessions() async throws -> [RecordingSession] {
        try await database.read { db in
            try Data.fetchAll(db, sql: "SELECT metadata FROM recording_sessions ORDER BY id").map { try JSONDecoder().decode(RecordingSession.self, from: $0) }
        }
    }

    public func discardRecordingSession(sessionID: RecordingSessionID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM recording_sessions WHERE id = ?", arguments: [sessionID.rawValue.uuidString])
        }
    }

    public func recordSessionError(_ error: LocalAudioError, sessionID: RecordingSessionID) async throws {
        try await database.write { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT metadata FROM recording_sessions WHERE id = ?", arguments: [sessionID.rawValue.uuidString]) else { return }
            var session = try JSONDecoder().decode(RecordingSession.self, from: data)
            session.localError = error
            try db.execute(sql: "UPDATE recording_sessions SET metadata = ? WHERE id = ?", arguments: [try JSONEncoder().encode(session), sessionID.rawValue.uuidString])
        }
    }

    public func acknowledgeDeletion(noteID: NoteID, endpoint: AttemptDevice) async throws {
        try await database.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO tombstone_acknowledgements (note_id, endpoint) VALUES (?, ?)", arguments: [noteID.rawValue.uuidString, endpoint.rawValue])
        }
    }

    public func deletions() async throws -> [DeletionTombstone] {
        try await database.read { db in
            try String.fetchAll(db, sql: "SELECT note_id FROM tombstones ORDER BY note_id").map { id in
                DeletionTombstone(noteID: NoteID(rawValue: UUID(uuidString: id)!),
                    recordingSessionID: try String.fetchOne(db, sql: "SELECT session_id FROM tombstones WHERE note_id = ?", arguments: [id]).flatMap(UUID.init(uuidString:)).map(RecordingSessionID.init(rawValue:)),
                    acknowledgedEndpoints: try String.fetchAll(db, sql: "SELECT endpoint FROM tombstone_acknowledgements WHERE note_id = ? ORDER BY endpoint", arguments: [id]).map { AttemptDevice(rawValue: $0)! })
            }
        }
    }

    private static func latestRevision(db: Database) throws -> ConfigurationRevision? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM configuration_revisions WHERE known_at IS NOT NULL ORDER BY known_at DESC, id DESC LIMIT 1") else { return nil }
        return ConfigurationRevision(id: ConfigurationRevisionID(rawValue: UUID(uuidString: row["id"])!),
            changedAt: Date(timeIntervalSince1970: row["known_at"]),
            endpoint: try JSONDecoder().decode(SanitizedEndpoint.self, from: row["endpoint"]))
    }

    public func latestConfigurationRevision() async throws -> ConfigurationRevision? {
        try await database.read { db in try Self.latestRevision(db: db) }
    }

    public func deliveryAttempts(noteID: NoteID) async throws -> [Attempt] {
        try await database.read { db in
            try Row.fetchAll(db,
                sql: "SELECT metadata FROM attempts WHERE note_id = ? AND metadata IS NOT NULL ORDER BY rowid",
                arguments: [noteID.rawValue.uuidString]).compactMap { row in
                    guard let metadata: Data = row["metadata"] else { return nil }
                    return try JSONDecoder().decode(Attempt.self, from: metadata)
                }
        }
    }

    public func reset() async throws {
        try await database.write { db in
            for table in ["tombstone_acknowledgements", "tombstones", "leases", "workflow_steps",
                          "receipts", "attempts", "deliveries", "notes", "recording_sessions",
                          "configuration_revisions"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }

    public func saveConfigurationRevision(_ revision: ConfigurationRevision) async throws {
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO configuration_revisions (id, known_at, endpoint) VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET known_at = excluded.known_at, endpoint = excluded.endpoint
                WHERE configuration_revisions.known_at IS NULL
                """, arguments: [revision.id.rawValue.uuidString, revision.changedAt.timeIntervalSince1970,
                    try JSONEncoder().encode(Self.sanitized(revision.endpoint))])
        }
    }

    public func configurationRevision(for noteID: NoteID) async throws -> ConfigurationRevision? {
        try await database.read { db in
            guard let note = try Self.readNote(id: noteID, db: db), note.isDeliveryEligible else { return nil }
            return try Self.latestRevision(db: db)
        }
    }

    public func send(noteID: NoteID) async throws {
        try await database.write { db in
            guard let note = try Self.readNote(id: noteID, db: db) else { throw WhimStoreError.missingNote }
            guard note.localError == nil else { throw WhimStoreError.notEligible }
            guard note.requiresReview else { return }
            let recording = FinalizedRecording(id: note.id, recordingSessionID: note.recordingSessionID, title: note.title,
                titleSource: note.titleSource, createdAt: note.createdAt, duration: note.duration, source: note.source,
                captureOutcome: note.captureOutcome, requiresReview: false, audioURL: note.audioURL)
            try db.execute(sql: "UPDATE notes SET metadata = ? WHERE id = ?", arguments: [try JSONEncoder().encode(recording), noteID.rawValue.uuidString])
        }
    }

    public func updateTitle(noteID: NoteID, title: String, source: TitleSource) async throws {
        try await database.write { db in
            guard let note = try Self.readNote(id: noteID, db: db) else { throw WhimStoreError.missingNote }
            let recording = FinalizedRecording(id: note.id, recordingSessionID: note.recordingSessionID,
                title: title, titleSource: source, createdAt: note.createdAt, duration: note.duration,
                source: note.source, captureOutcome: note.captureOutcome, requiresReview: note.requiresReview,
                audioURL: note.audioURL)
            try db.execute(sql: "UPDATE notes SET metadata = ? WHERE id = ?",
                arguments: [try JSONEncoder().encode(recording), noteID.rawValue.uuidString])
        }
    }

    public func listNotes(filter: NoteFilter) async throws -> [NoteProjection] {
        let time = now(), connected = isConnected
        return try await database.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM notes ORDER BY created_at DESC, id ASC").compactMap { rawID in
                guard let note = try Self.readNote(id: NoteID(rawValue: UUID(uuidString: rawID)!), db: db, time: time, connected: connected) else { return nil }
                let projection = NoteProjection(note: note)
                guard filter == .all || filter.rawValue == projection.status.rawValue else { return nil }
                return projection
            }
        }
    }
    public func apply(_ event: DeliveryEvent, to noteID: NoteID) async throws -> Delivery {
        if case .connectivityChanged(let connected) = event { isConnected = connected }
        _ = try await database.write { db in
            guard let note = try Self.readNote(id: noteID, db: db) else { throw WhimStoreError.missingNote }
            switch event {
            case .attemptStarted(let attempt):
                guard attempt.noteID == noteID else { throw WhimStoreError.invalidEvent }
                guard !note.requiresReview, note.localError == nil else { throw WhimStoreError.notEligible }
            case .attemptFailed(let failure):
                guard failure.attempt.noteID == noteID else { throw WhimStoreError.invalidEvent }
            case .receipt(let receipt):
                guard receipt.noteID == noteID else { throw WhimStoreError.invalidEvent }
                if let persistedNoteID = try String.fetchOne(db, sql: "SELECT note_id FROM attempts WHERE id = ?", arguments: [receipt.attemptID.rawValue.uuidString]) {
                    guard persistedNoteID == noteID.rawValue.uuidString else { throw WhimStoreError.invalidEvent }
                } else {
                    try db.execute(sql: "INSERT INTO attempts (id, note_id) VALUES (?, ?)", arguments: [receipt.attemptID.rawValue.uuidString, noteID.rawValue.uuidString])
                }
            default:
                break
            }
            let sanitizedEvent: DeliveryEvent
            switch event {
            case .attemptStarted(let attempt): sanitizedEvent = .attemptStarted(Self.sanitized(attempt))
            case .attemptFailed(let failure):
                sanitizedEvent = .attemptFailed(AttemptFailure(attempt: Self.sanitized(failure.attempt), failedAt: failure.failedAt,
                    reason: failure.reason, retryAfter: failure.retryAfter, responseExcerpt: failure.responseExcerpt))
            default: sanitizedEvent = event
            }
            switch sanitizedEvent {
            case .attemptStarted(let attempt):
                try Self.persist(attempt, noteID: noteID, db: db)
            case .attemptFailed(let failure):
                try Self.persist(failure.attempt, noteID: noteID, db: db)
            case .workflowFailed(let error):
                try db.execute(sql: "UPDATE deliveries SET workflow_error = ? WHERE note_id = ?",
                    arguments: [error.rawValue, noteID.rawValue.uuidString])
            case .receipt:
                try db.execute(sql: "UPDATE deliveries SET workflow_error = NULL WHERE note_id = ?",
                    arguments: [noteID.rawValue.uuidString])
            default:
                break
            }
            let reduced = DeliveryReducer.reduce(note.delivery, event: sanitizedEvent)
            for attempt in reduced.activeAttempts + reduced.failedAttempts.map(\.attempt) {
                try Self.persist(attempt, noteID: noteID, db: db)
            }
            for failure in reduced.failedAttempts {
                try db.execute(sql: "UPDATE attempts SET failure = ? WHERE id = ? AND note_id = ?", arguments: [try JSONEncoder().encode(failure), failure.attempt.id.rawValue.uuidString, noteID.rawValue.uuidString])
            }
            if let receipt = reduced.receipt {
                try db.execute(sql: "INSERT OR IGNORE INTO receipts (attempt_id, note_id, metadata) VALUES (?, ?, ?)", arguments: [receipt.attemptID.rawValue.uuidString, noteID.rawValue.uuidString, try JSONEncoder().encode(receipt)])
            }
            return try Self.readNote(id: noteID, db: db)!.delivery
        }
        return try await note(id: noteID)!.delivery
    }

    private static func sanitized(_ attempt: Attempt) -> Attempt {
        return Attempt(id: attempt.id, noteID: attempt.noteID, configurationRevisionID: attempt.configurationRevisionID,
            device: attempt.device, endpoint: Self.sanitized(attempt.endpoint), startedAt: attempt.startedAt,
            retryCycle: attempt.retryCycle)
    }

    private static func sanitized(_ endpoint: SanitizedEndpoint) -> SanitizedEndpoint {
        SanitizedEndpoint(scheme: endpoint.scheme, host: endpoint.host, port: endpoint.port,
            path: String(endpoint.path.prefix { $0 != "?" && $0 != "#" }))
    }

    private static func persist(_ attempt: Attempt, noteID: NoteID, db: Database) throws {
        try db.execute(sql: "INSERT OR IGNORE INTO configuration_revisions (id) VALUES (?)", arguments: [attempt.configurationRevisionID.rawValue.uuidString])
        try db.execute(sql: """
            INSERT INTO attempts (id, note_id, revision_id, metadata) VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET revision_id = excluded.revision_id, metadata = excluded.metadata
            WHERE attempts.note_id = excluded.note_id
            """, arguments: [attempt.id.rawValue.uuidString, noteID.rawValue.uuidString,
                attempt.configurationRevisionID.rawValue.uuidString, try JSONEncoder().encode(attempt)])
        guard db.changesCount == 1 else { throw WhimStoreError.invalidEvent }
    }

    public func acquireLease(_ kind: LeaseKind, noteID: NoteID, owner: UUID, until: Date) async throws -> Bool {
        let time = now()
        guard until > time else { return false }
        return try await database.write { db in
            try db.execute(sql: """
                INSERT INTO leases (note_id, kind, owner, expires_at) VALUES (?, ?, ?, ?)
                ON CONFLICT(note_id, kind) DO UPDATE SET owner = excluded.owner, expires_at = excluded.expires_at
                WHERE leases.expires_at <= ? OR leases.owner = excluded.owner
                """, arguments: [noteID.rawValue.uuidString, kind.rawValue, owner.uuidString, until.timeIntervalSince1970, time.timeIntervalSince1970])
            return db.changesCount == 1
        }
    }

    public func releaseLease(_ kind: LeaseKind, noteID: NoteID, owner: UUID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM leases WHERE note_id = ? AND kind = ? AND owner = ?", arguments: [noteID.rawValue.uuidString, kind.rawValue, owner.uuidString])
        }
    }

    public func beginRetryCycle(noteID: NoteID) async throws -> Bool {
        try await database.write { db in
            guard let note = try Self.readNote(id: noteID, db: db), note.delivery.receipt == nil,
                  note.delivery.status == .failed else { return false }
            try db.execute(sql: "UPDATE deliveries SET retry_cycle = retry_cycle + 1, notified_cycle = NULL, workflow_error = NULL WHERE note_id = ?",
                arguments: [noteID.rawValue.uuidString])
            return db.changesCount == 1
        }
    }

    public func markExhaustionNotified(noteID: NoteID, retryCycle: Int) async throws -> Bool {
        try await database.write { db in
            try db.execute(sql: """
                UPDATE deliveries SET notified_cycle = ?
                WHERE note_id = ? AND retry_cycle = ?
                  AND (notified_cycle IS NULL OR notified_cycle != ?)
                """, arguments: [retryCycle, noteID.rawValue.uuidString, retryCycle, retryCycle])
            return db.changesCount == 1
        }
    }
}
