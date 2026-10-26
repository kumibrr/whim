import Foundation
import GRDB
import CryptoKit

/// Protocol durability lives beside canonical tables; it survives WhimStore.reset().
struct ConnectivityJournal: Sendable {
    private let database: DatabaseQueue
    init(databaseURL: URL) throws {
        var config = Configuration(); config.busyMode = .timeout(5)
        database = try DatabaseQueue(path: databaseURL.path, configuration: config)
        try database.write { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS peer_applied (id TEXT PRIMARY KEY NOT NULL)")
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS peer_inbox (id TEXT PRIMARY KEY, envelope BLOB NOT NULL)")
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS peer_outbox (key TEXT PRIMARY KEY, id TEXT NOT NULL, envelope BLOB NOT NULL, file TEXT, submitted INTEGER NOT NULL DEFAULT 0)")
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS peer_state (key TEXT PRIMARY KEY, value BLOB NOT NULL)")
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS peer_audio_handoffs (note_id TEXT NOT NULL, generation_key TEXT NOT NULL, generation BLOB NOT NULL, accepted INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (note_id, generation_key))")
            // Older builds recorded valid handoff acceptance on file outbox entries.
            // Preserve that evidence when introducing independent retention holds.
            for data in try Data.fetchAll(db, sql: "SELECT envelope FROM peer_outbox WHERE file IS NOT NULL AND submitted = 2") {
                let envelope = try ConnectivityEnvelope.decode(data)
                if let noteID = envelope.payload.noteID {
                    try Self.acceptAudioHandoff(noteID, generation: envelope.generation, db: db)
                }
            }
        }
    }
    func append(_ envelope: ConnectivityEnvelope) throws {
        try database.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO peer_inbox (id, envelope) VALUES (?, ?)",
                arguments: [envelope.messageID.uuidString, try envelope.sanitized.encoded()])
        }
    }
    func inbox() throws -> [ConnectivityEnvelope] {
        try database.read { db in
            try Data.fetchAll(db, sql: "SELECT envelope FROM peer_inbox ORDER BY id").map(ConnectivityEnvelope.decode)
        }
    }
    struct Outgoing: Sendable { let envelope: ConnectivityEnvelope; let file: URL? }
    func pendingAudioNoteIDs() throws -> Set<NoteID> {
        try database.read { db in
            var ids = Set(try Data.fetchAll(db, sql: "SELECT envelope FROM peer_outbox WHERE file IS NOT NULL AND submitted != 2")
                .compactMap { try ConnectivityEnvelope.decode($0).payload.noteID })
            ids.formUnion(try String.fetchAll(db, sql: "SELECT note_id FROM peer_audio_handoffs WHERE accepted = 0")
                .compactMap { UUID(uuidString: $0).map { NoteID(rawValue: $0) } })
            return ids
        }
    }
    func beginAudioHandoff(_ noteID: NoteID, generation: ResetGeneration) throws {
        try database.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO peer_audio_handoffs (note_id, generation_key, generation) VALUES (?, ?, ?)",
                arguments: [noteID.rawValue.uuidString, Self.generationKey(generation), try PropertyListEncoder().encode(generation)])
        }
    }
    private static func generationKey(_ generation: ResetGeneration) -> String {
        String(generation.counter) + "_" + generation.origin.uuidString
    }
    private static func acceptAudioHandoff(_ noteID: NoteID, generation: ResetGeneration, db: Database) throws {
        try db.execute(sql: "INSERT INTO peer_audio_handoffs (note_id, generation_key, generation, accepted) VALUES (?, ?, ?, 1) ON CONFLICT (note_id, generation_key) DO UPDATE SET accepted = 1",
            arguments: [noteID.rawValue.uuidString, generationKey(generation), try PropertyListEncoder().encode(generation)])
    }
    func enqueue(_ envelope: ConnectivityEnvelope, file: URL? = nil, resubmit: Bool = false, reset: ResetState? = nil) throws {
        try database.write { db in try Self.enqueue(envelope, file: file, resubmit: resubmit, reset: reset, db: db) }
    }
    private static func enqueue(_ envelope: ConnectivityEnvelope, file: URL? = nil, resubmit: Bool = false,
                                reset: ResetState? = nil, db: Database) throws {
        struct Identity: Encodable { let generation: ResetGeneration; let payload: ConnectivityEnvelope.Payload; let file: Bool }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let key = SHA256.hash(data: try encoder.encode(Identity(generation: envelope.generation,
            payload: envelope.payload, file: file != nil))).map { String(format: "%02x", $0) }.joined()
        if let reset {
            try db.execute(sql: "INSERT OR REPLACE INTO peer_state (key, value) VALUES ('reset', ?)",
                arguments: [try PropertyListEncoder().encode(reset)])
        }
        try db.execute(sql: "INSERT OR IGNORE INTO peer_outbox (key, id, envelope, file) VALUES (?, ?, ?, ?)",
            arguments: [key, envelope.messageID.uuidString, try envelope.sanitized.encoded(), file?.path])
        if resubmit { try db.execute(sql: "UPDATE peer_outbox SET submitted = 0 WHERE key = ?", arguments: [key]) }
    }
    func outgoing() throws -> [Outgoing] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT envelope, file FROM peer_outbox WHERE submitted = 0 ORDER BY rowid").map { row in
                Outgoing(envelope: try ConnectivityEnvelope.decode(row["envelope"]),
                    file: (row["file"] as String?).map { URL(fileURLWithPath: $0) })
            }
        }
    }
    func submitted(_ id: UUID, value: Bool = true) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE peer_outbox SET submitted = ? WHERE id = ?", arguments: [value, id.uuidString])
        }
    }

    func wasApplied(_ id: UUID) throws -> Bool {
        try database.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM peer_applied WHERE id = ?)", arguments: [id.uuidString]) == true
        }
    }
    func markApplied(_ id: UUID) throws {
        try database.write { db in try db.execute(sql: "INSERT OR IGNORE INTO peer_applied (id) VALUES (?)", arguments: [id.uuidString]) }
    }

    func acknowledge(_ id: UUID, durableOnly: Bool = false) throws {
        try database.write { db in
            if durableOnly, let row = try Row.fetchOne(db, sql: "SELECT envelope, file FROM peer_outbox WHERE id = ?", arguments: [id.uuidString]) {
                let envelope = try ConnectivityEnvelope.decode(row["envelope"])
                switch envelope.payload { case .deletion, .reset: return; default: break }
                let file: String? = row["file"]
                if file != nil, let noteID = envelope.payload.noteID {
                    try Self.acceptAudioHandoff(noteID, generation: envelope.generation, db: db)
                }
            }
            try db.execute(sql: "UPDATE peer_outbox SET submitted = 2 WHERE id = ?", arguments: [id.uuidString])
        }
    }
    func acknowledgeApplied(_ payload: ConnectivityEnvelope.Payload, generation: ResetGeneration) throws {
        try database.write { db in
            for data in try Data.fetchAll(db, sql: "SELECT envelope FROM peer_outbox WHERE submitted != 2") {
                let envelope = try ConnectivityEnvelope.decode(data)
                if envelope.generation == generation && envelope.payload == payload {
                    try db.execute(sql: "UPDATE peer_outbox SET submitted = 2 WHERE id = ?", arguments: [envelope.messageID.uuidString])
                }
            }
        }
    }
    func acknowledgeAudio(_ noteID: NoteID, generation: ResetGeneration) throws {
        try database.write { db in
            try Self.acceptAudioHandoff(noteID, generation: generation, db: db)
            for row in try Row.fetchAll(db, sql: "SELECT id, envelope FROM peer_outbox WHERE file IS NOT NULL AND submitted != 2") {
                let envelope = try ConnectivityEnvelope.decode(row["envelope"])
                if envelope.generation == generation, envelope.payload.noteID == noteID {
                    try db.execute(sql: "UPDATE peer_outbox SET submitted = 2 WHERE id = ?", arguments: [row["id"] as String])
                }
            }
        }
    }
    /// Read canonical synchronization and reconcile its outbox in one transaction.
    /// A suspended process must never retire a request using an older Note snapshot.
    func reconcileAudioRequest(_ noteID: NoteID, generation: ResetGeneration) throws {
        try database.write { db in
            let reset = try Data.fetchOne(db, sql: "SELECT value FROM peer_state WHERE key = 'reset'")
                .map { try PropertyListDecoder().decode(ResetState.self, from: $0) }
            guard generation == (reset?.generation ?? .initial), reset?.complete != false else { return }
            let synchronization = try Data.fetchOne(db, sql: "SELECT audio_synchronization FROM notes WHERE id = ?",
                arguments: [noteID.rawValue.uuidString]).map { try JSONDecoder().decode(AudioSynchronization.self, from: $0) }
            let current = synchronization?.status == .retrying ? synchronization?.requestID : nil
            for row in try Row.fetchAll(db, sql: "SELECT id, envelope FROM peer_outbox WHERE submitted != 2") {
                let envelope = try ConnectivityEnvelope.decode(row["envelope"])
                if envelope.generation == generation, case .audioRequest(let request) = envelope.payload,
                   request.noteID == noteID, request.requestID != current {
                    try db.execute(sql: "UPDATE peer_outbox SET submitted = 2 WHERE id = ?", arguments: [row["id"] as String])
                }
            }
            if let current {
                try Self.enqueue(.init(messageID: current, generation: generation,
                    payload: .audioRequest(.init(noteID: noteID, requestID: current))), db: db)
            }
        }
    }
    func replayUnacknowledged() throws {
        try database.write { db in try db.execute(sql: "UPDATE peer_outbox SET submitted = 0 WHERE submitted = 1") }
    }

    func discardNotePayloads(_ id: NoteID) throws {
        try discard { envelope in
            guard envelope.payload.noteID == id else { return false }
            if case .deletion = envelope.payload { return false }
            return true
        }
        try database.write { db in try db.execute(sql: "DELETE FROM peer_audio_handoffs WHERE note_id = ?", arguments: [id.rawValue.uuidString]) }
    }
    func discard(before generation: ResetGeneration) throws {
        try discard { $0.generation < generation }
        try database.write { db in
            for row in try Row.fetchAll(db, sql: "SELECT note_id, generation_key, generation FROM peer_audio_handoffs") {
                if try PropertyListDecoder().decode(ResetGeneration.self, from: row["generation"]) < generation {
                    try db.execute(sql: "DELETE FROM peer_audio_handoffs WHERE note_id = ? AND generation_key = ?",
                        arguments: [row["note_id"] as String, row["generation_key"] as String])
                }
            }
        }
    }
    private func discard(where predicate: @Sendable (ConnectivityEnvelope) -> Bool) throws {
        try database.write { db in
            for table in ["peer_inbox", "peer_outbox"] {
                for row in try Row.fetchAll(db, sql: "SELECT id, envelope FROM \(table)") {
                    let envelope = try ConnectivityEnvelope.decode(row["envelope"])
                    if predicate(envelope) {
                        let id: String = row["id"]
                        try db.execute(sql: "DELETE FROM \(table) WHERE id = ?", arguments: [id])
                        try db.execute(sql: "DELETE FROM peer_applied WHERE id = ?", arguments: [id])
                    }
                }
            }
        }
    }

    func read<T: Decodable>(_ key: String, as type: T.Type) throws -> T? {
        try database.read { db in
            try Data.fetchOne(db, sql: "SELECT value FROM peer_state WHERE key = ?", arguments: [key])
                .map { try PropertyListDecoder().decode(T.self, from: $0) }
        }
    }
    func write<T: Encodable>(_ value: T, key: String) throws {
        try database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO peer_state (key, value) VALUES (?, ?)",
                arguments: [key, try PropertyListEncoder().encode(value)])
        }
    }
    struct ResetState: Codable { let generation: ResetGeneration; let complete: Bool }
    func resetState() throws -> ResetState { try read("reset", as: ResetState.self) ?? .init(generation: .initial, complete: true) }
}
