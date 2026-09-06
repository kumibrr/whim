import GRDB

enum WhimDatabaseMigrator {
    static func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE recording_sessions (id TEXT PRIMARY KEY NOT NULL, metadata BLOB NOT NULL);
                CREATE TABLE notes (
                    id TEXT PRIMARY KEY NOT NULL,
                    session_id TEXT NOT NULL UNIQUE,
                    created_at DOUBLE NOT NULL,
                    metadata BLOB NOT NULL,
                    local_error TEXT
                );
                CREATE TABLE deliveries (
                    note_id TEXT PRIMARY KEY NOT NULL REFERENCES notes(id) ON DELETE CASCADE
                );
                CREATE TABLE configuration_revisions (id TEXT PRIMARY KEY NOT NULL, known_at DOUBLE, endpoint BLOB);
                CREATE TABLE attempts (
                    id TEXT PRIMARY KEY NOT NULL,
                    note_id TEXT NOT NULL REFERENCES deliveries(note_id) ON DELETE CASCADE,
                    revision_id TEXT REFERENCES configuration_revisions(id),
                    metadata BLOB,
                    failure BLOB,
                    UNIQUE (id, note_id)
                );
                CREATE TABLE receipts (
                    attempt_id TEXT PRIMARY KEY NOT NULL,
                    note_id TEXT NOT NULL,
                    metadata BLOB NOT NULL,
                    FOREIGN KEY (attempt_id, note_id) REFERENCES attempts(id, note_id) ON DELETE CASCADE
                );
                CREATE TABLE workflow_steps (
                    note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                    step_id TEXT NOT NULL,
                    PRIMARY KEY (note_id, step_id)
                );
                CREATE TABLE leases (
                    note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL, owner TEXT NOT NULL, expires_at DOUBLE NOT NULL,
                    PRIMARY KEY (note_id, kind)
                );
                CREATE TABLE tombstones (note_id TEXT PRIMARY KEY NOT NULL, session_id TEXT);
                CREATE TABLE tombstone_acknowledgements (
                    note_id TEXT NOT NULL REFERENCES tombstones(note_id) ON DELETE CASCADE,
                    endpoint TEXT NOT NULL,
                    PRIMARY KEY (note_id, endpoint)
                );
                """)
        }
        migrator.registerMigration("v2-delivery-retry-cycles") { db in
            try db.alter(table: "deliveries") { table in
                table.add(column: "retry_cycle", .integer).notNull().defaults(to: 0)
                table.add(column: "notified_cycle", .integer)
            }
        }
        migrator.registerMigration("v3-delivery-workflow-error") { db in
            try db.alter(table: "deliveries") { table in
                table.add(column: "workflow_error", .text)
            }
        }
        try migrator.migrate(queue)
    }
}
