import Foundation
import XCTest
@testable import WhimCore

final class RecoveryTests: XCTestCase {
    // Break: one corrupt durable orphan aborts startup and prevents other sessions from recovering.
    func testCorruptDurableOrphanBecomesVisibleAndDoesNotAbortRecovery() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let files = try AudioFileStore(root: h.root, closeWriter: { _ in })
        let corruptID = NoteID()
        try Data("not an audio container".utf8).write(to: files.audioURL(for: corruptID))
        let playable = RecordingSession(id: RecordingSessionID(), noteID: NoteID(), createdAt: Date(), source: .iphone)
        try await h.store.saveRecordingSession(playable)
        try writeAudioFixture(to: files.temporaryURL(for: playable.id))

        let scanner = RecoveryScanner(store: h.store, files: files)
        try await scanner.scan()
        try await scanner.scan()

        let corrupt = try await h.store.note(id: corruptID)
        let recovered = try await h.store.note(id: playable.noteID)
        XCTAssertEqual(corrupt?.localError, .unreadable)
        XCTAssertEqual(corrupt?.requiresReview, true)
        XCTAssertEqual(recovered?.captureOutcome, .recovered)
    }

    // Break: missing and empty unfinished audio vanish from the timeline without a deletable error.
    func testMissingAndEmptyTemporarySessionsRemainVisibleUntilDelete() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let files = try AudioFileStore(root: h.root, closeWriter: { _ in })
        let missing = RecordingSession(id: RecordingSessionID(), noteID: NoteID(), createdAt: Date(), source: .iphone)
        let empty = RecordingSession(id: RecordingSessionID(), noteID: NoteID(), createdAt: Date(), source: .iphone)
        try await h.store.saveRecordingSession(missing)
        try await h.store.saveRecordingSession(empty)
        _ = FileManager.default.createFile(atPath: try files.temporaryURL(for: empty.id).path, contents: Data())

        let scanner = RecoveryScanner(store: h.store, files: files)
        try await scanner.scan()
        try await scanner.scan()

        let missingNote = try await h.store.note(id: missing.noteID)
        let emptyNote = try await h.store.note(id: empty.noteID)
        let failed = try await h.store.listNotes(filter: .failed)
        XCTAssertEqual(missingNote?.localError, .missing)
        XCTAssertEqual(emptyNote?.localError, .unreadable)
        XCTAssertEqual(failed.count, 2)
    }

    // Break: a file left after tombstoning is recovered again, or Delete leaves unreadable audio behind.
    func testTombstonedDurableFileIsRemovedWithoutResurrection() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let files = try AudioFileStore(root: h.root, closeWriter: { _ in })
        let recording = try h.recording()
        try writeAudioFixture(to: files.temporaryURL(for: recording.recordingSessionID))
        let note = try await files.finalize(recording, in: h.store)
        try await h.store.delete(noteID: note.id)
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        try await RecoveryScanner(store: reopened, files: files).scan()
        try await RecoveryScanner(store: reopened, files: files).scan()
        let rows = try await reopened.listNotes(filter: .all)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.audioURL.path))
    }

    // Break: a database Note points at missing or corrupt audio while still appearing playable.
    func testMissingAndCorruptFinalizedAudioRemainVisibleAcrossRescans() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let files = try AudioFileStore(root: h.root, closeWriter: { _ in })
        var ids: [NoteID] = []
        for error in [LocalAudioError.missing, .unreadable] {
            let recording = try h.recording()
            try writeAudioFixture(to: files.temporaryURL(for: recording.recordingSessionID))
            let note = try await files.finalize(recording, in: h.store)
            ids.append(note.id)
            if error == .missing { try FileManager.default.removeItem(at: note.audioURL) }
            else { try Data([1, 2, 3]).write(to: note.audioURL) }
        }
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        let scanner = RecoveryScanner(store: reopened, files: files)
        try await scanner.scan()
        try await scanner.scan()
        let missing = try await reopened.note(id: ids[0])
        let corrupt = try await reopened.note(id: ids[1])
        let rows = try await reopened.listNotes(filter: .failed)
        XCTAssertEqual(missing?.localError, .missing)
        XCTAssertEqual(corrupt?.localError, .unreadable)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { !$0.hasLocalAudio })
        XCTAssertFalse(missing!.isDeliveryEligible)
    }

    // Break: audio moved before the metadata transaction is lost or recovered under a different ID.
    func testDurableOrphansReconcileByFilenameWithAndWithoutSession() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let files = try AudioFileStore(root: h.root, closeWriter: { _ in })
        let known = RecordingSession(id: RecordingSessionID(), noteID: NoteID(), createdAt: Date(timeIntervalSince1970: 100), source: .appleWatch)
        let orphan = RecordingSession(id: RecordingSessionID(), noteID: NoteID(), createdAt: Date(), source: .iphone)
        try await h.store.saveRecordingSession(known)
        for session in [known, orphan] {
            try writeAudioFixture(to: files.temporaryURL(for: session.id))
            _ = try files.finalize(sessionID: session.id, noteID: session.noteID)
        }
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        try await RecoveryScanner(store: reopened, files: files).scan()
        try await RecoveryScanner(store: reopened, files: files).scan()
        let rows = try await reopened.listNotes(filter: .all)
        let preserved = try await reopened.note(id: known.noteID)
        XCTAssertEqual(Set(rows.map(\.id)), Set([known.noteID, orphan.noteID]))
        XCTAssertTrue(rows.allSatisfy(\.requiresReview))
        XCTAssertEqual(preserved?.createdAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(preserved?.source, .appleWatch)
    }

    // Break: an unreadable temporary file aborts startup or disappears without a visible error.
    func testUnreadableTemporaryRemnantIsVisibleUntilDelete() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let session = RecordingSession(id: RecordingSessionID(), noteID: NoteID(), createdAt: Date(), source: .iphone)
        try await h.store.saveRecordingSession(session)
        let files = try AudioFileStore(root: h.root, closeWriter: { _ in })
        try Data("not an audio container".utf8).write(to: files.temporaryURL(for: session.id))
        let scanner = RecoveryScanner(store: h.store, files: files)
        try await scanner.scan()
        try await scanner.scan()
        let note = try await h.store.note(id: session.noteID)
        let rows = try await h.store.listNotes(filter: .all)
        XCTAssertEqual(note?.localError, .unreadable)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.status, .failed)
        XCTAssertEqual(rows.first?.hasLocalAudio, false)
        do { try await h.store.send(noteID: session.noteID); XCTFail("Unreadable recording sent") }
        catch WhimStoreError.notEligible { }
        try await h.store.delete(noteID: session.noteID)
        try await scanner.scan()
        let deleted = try await h.store.listNotes(filter: .all)
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try files.temporaryURL(for: session.id).path))
    }

    // Break: recovering playable audio silently schedules delivery before explicit Send.
    func testExplicitSendIsRequiredBeforeRecoveredDeliveryCanStart() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let session = RecordingSession(id: RecordingSessionID(), noteID: NoteID(), createdAt: Date(), source: .iphone)
        try await h.store.saveRecordingSession(session)
        let files = try AudioFileStore(root: h.root, closeWriter: { _ in })
        try writeAudioFixture(to: files.temporaryURL(for: session.id))
        try await RecoveryScanner(store: h.store, files: files).scan()
        let revision = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: Date(), endpoint: SanitizedEndpoint(scheme: "https", host: "example.com", path: "/"))
        try await h.store.saveConfigurationRevision(revision)
        let before = try await h.store.configurationRevision(for: session.noteID)
        XCTAssertNil(before)
        let attempt = Attempt(noteID: session.noteID, configurationRevisionID: revision.id, device: .iphone, endpoint: revision.endpoint, startedAt: Date())
        do { _ = try await h.store.apply(.attemptStarted(attempt), to: session.noteID); XCTFail("Recovery started Delivery") }
        catch WhimStoreError.notEligible { }
        try await h.store.send(noteID: session.noteID)
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        let after = try await reopened.configurationRevision(for: session.noteID)
        let sent = try await reopened.note(id: session.noteID)
        XCTAssertEqual(after?.id, revision.id)
        XCTAssertFalse(sent!.requiresReview)
        XCTAssertTrue(sent!.isDeliveryEligible)
    }

    // Break: restart loses a playable Recording Session or recovers it more than once.
    func testPlayableTemporarySessionRecoversOnceAndWaitsForReview() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let session = RecordingSession(id: RecordingSessionID(), noteID: NoteID(), createdAt: Date(timeIntervalSince1970: 100), source: .appleWatch)
        try await h.store.saveRecordingSession(session)
        let files = try AudioFileStore(root: h.root, closeWriter: { _ in })
        try writeAudioFixture(to: files.temporaryURL(for: session.id))
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        let scanner = RecoveryScanner(store: reopened, files: files)
        try await scanner.scan()
        try await scanner.scan()
        let rows = try await reopened.listNotes(filter: .all)
        let note = try await reopened.note(id: session.noteID)
        let sessions = try await reopened.recordingSessions()
        XCTAssertEqual(rows.map(\.id), [session.noteID])
        XCTAssertEqual(note?.title, "Recovered recording")
        XCTAssertEqual(note?.titleSource, .recovered)
        XCTAssertEqual(note?.captureOutcome, .recovered)
        XCTAssertEqual(note?.source, .appleWatch)
        XCTAssertTrue(note!.requiresReview)
        XCTAssertFalse(note!.isDeliveryEligible)
        XCTAssertTrue(sessions.isEmpty)
    }
}
