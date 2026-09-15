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
    func enqueue(_ envelope: ConnectivityEnvelope, file: URL? = nil, resubmit: Bool = false) throws {
        struct Identity: Encodable { let generation: ResetGeneration; let payload: ConnectivityEnvelope.Payload; let file: Bool }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let key = SHA256.hash(data: try encoder.encode(Identity(generation: envelope.generation,
            payload: envelope.payload, file: file != nil))).map { String(format: "%02x", $0) }.joined()
        try database.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO peer_outbox (key, id, envelope, file) VALUES (?, ?, ?, ?)",
                arguments: [key, envelope.messageID.uuidString, try envelope.sanitized.encoded(), file?.path])
            if resubmit { try db.execute(sql: "UPDATE peer_outbox SET submitted = 0 WHERE key = ?", arguments: [key]) }
        }
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

    func acknowledge(_ id: UUID) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE peer_outbox SET submitted = 2 WHERE id = ?", arguments: [id.uuidString])
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
    }
    func discard(before generation: ResetGeneration) throws {
        try discard { $0.generation < generation }
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
