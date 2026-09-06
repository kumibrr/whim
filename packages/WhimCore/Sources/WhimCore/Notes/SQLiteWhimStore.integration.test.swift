import Foundation
import AVFoundation
import GRDB
import XCTest
@testable import WhimCore

final class PersistenceTests: XCTestCase {
    // Break: a database created before workflow failures existed can no longer open or persist the new state.
    func testV2DatabaseMigratesWorkflowFailureAcrossReopen() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let note = try await h.store.saveFinalized(h.recording())
        let priorSchema = try DatabaseQueue(path: h.databaseURL.path)
        try await priorSchema.write { db in
            try db.execute(sql: "ALTER TABLE deliveries DROP COLUMN workflow_error")
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                arguments: ["v3-delivery-workflow-error"])
        }

        let migrated: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        _ = try await migrated.apply(.workflowFailed(.deliveryPreparationFailed), to: note.id)
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        let persisted = try await reopened.note(id: note.id)

        XCTAssertEqual(persisted?.delivery.workflowError, .deliveryPreparationFailed)
        XCTAssertEqual(persisted?.delivery.status, .failed)
    }

    // Break: manual Retry state disappears on restart, erases history, or remains exhausted.
    func testManualRetryCycleAndNotificationMarkerPersistAcrossReopen() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let note = try await h.store.saveFinalized(h.recording())
        let revision = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: Date(),
            endpoint: SanitizedEndpoint(scheme: "https", host: "example.com", path: "/hook"))
        try await h.store.saveConfigurationRevision(revision)
        for offset in 0..<3 {
            let attempt = Attempt(noteID: note.id, configurationRevisionID: revision.id, device: .iphone,
                endpoint: revision.endpoint, startedAt: Date(timeIntervalSince1970: Double(offset)), retryCycle: 0)
            _ = try await h.store.apply(.attemptFailed(.init(attempt: attempt, failedAt: Date(), reason: .network)), to: note.id)
        }
        let began = try await h.store.beginRetryCycle(noteID: note.id)
        let firstMarker = try await h.store.markExhaustionNotified(noteID: note.id, retryCycle: 1)
        let duplicateMarker = try await h.store.markExhaustionNotified(noteID: note.id, retryCycle: 1)
        XCTAssertTrue(began)
        XCTAssertTrue(firstMarker)
        XCTAssertFalse(duplicateMarker)
        let freshAttempt = Attempt(noteID: note.id, configurationRevisionID: revision.id, device: .iphone,
            endpoint: revision.endpoint, startedAt: Date(), retryCycle: 1)
        _ = try await h.store.apply(.attemptFailed(.init(attempt: freshAttempt, failedAt: Date(), reason: .network)), to: note.id)

        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        let persisted = try await reopened.note(id: note.id)!
        XCTAssertEqual(persisted.delivery.currentRetryCycle, 1)
        XCTAssertEqual(persisted.delivery.failedAttempts.count, 4)
        XCTAssertEqual(persisted.delivery.status, .queued)
        let reopenedMarker = try await reopened.markExhaustionNotified(noteID: note.id, retryCycle: 1)
        XCTAssertFalse(reopenedMarker)
    }

    // Break: retrying an imported Note inserts a duplicate or resets its persisted Delivery state.
    func testFinalizedImportReplayIsIdempotent() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let recording = try h.recording()
        let note = try await h.store.saveFinalized(recording)
        let attempt = Attempt(noteID: note.id, configurationRevisionID: ConfigurationRevisionID(), device: .appleWatch,
            endpoint: SanitizedEndpoint(scheme: "https", host: "example.com", path: "/hook"), startedAt: Date())
        _ = try await h.store.apply(.attemptStarted(attempt), to: note.id)
        let receipt = Receipt(attemptID: attempt.id, noteID: note.id, receivedAt: Date(), statusCode: 204)
        _ = try await h.store.apply(.receipt(receipt), to: note.id)

        let replayed = try await h.store.saveFinalized(recording)
        let rows = try await h.store.listNotes(filter: .all)

        XCTAssertEqual(replayed.delivery.receipt, receipt)
        XCTAssertEqual(rows.map(\.id), [note.id])
    }

    // Break: an out-of-order cross-device Receipt is rejected or lost before its Attempt arrives.
    func testReceiptBeforeAttemptRemainsAbsorbingAcrossReopen() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let note = try await h.store.saveFinalized(h.recording())
        let attempt = Attempt(noteID: note.id, configurationRevisionID: ConfigurationRevisionID(), device: .appleWatch,
            endpoint: SanitizedEndpoint(scheme: "https", host: "example.com", path: "/hook"), startedAt: Date())
        let receipt = Receipt(attemptID: attempt.id, noteID: note.id, receivedAt: Date(), statusCode: 204)

        _ = try await h.store.apply(.receipt(receipt), to: note.id)
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        _ = try await reopened.apply(.attemptStarted(attempt), to: note.id)
        let persisted = try await reopened.note(id: note.id)

        XCTAssertEqual(persisted?.delivery.status, .sent)
        XCTAssertEqual(persisted?.delivery.receipt, receipt)
        XCTAssertTrue(persisted?.delivery.activeAttempts.isEmpty == true)
    }

    // Break: an event carrying another Note ID mutates the target Note's Delivery.
    func testDeliveryEventsCannotCrossNoteIdentity() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let target = try await h.store.saveFinalized(h.recording())
        let other = try await h.store.saveFinalized(h.recording())
        let attempt = Attempt(noteID: other.id, configurationRevisionID: ConfigurationRevisionID(), device: .iphone,
            endpoint: SanitizedEndpoint(scheme: "https", host: "example.com", path: "/hook"), startedAt: Date())

        do {
            _ = try await h.store.apply(.attemptStarted(attempt), to: target.id)
            XCTFail("Cross-Note Attempt was accepted")
        } catch { }
        let receipt = Receipt(attemptID: attempt.id, noteID: other.id, receivedAt: Date(), statusCode: 204)
        do {
            _ = try await h.store.apply(.receipt(receipt), to: target.id)
            XCTFail("Cross-Note Receipt was accepted")
        } catch { }

        let unchanged = try await h.store.note(id: target.id)
        XCTAssertTrue(unchanged?.delivery.activeAttempts.isEmpty == true)
        XCTAssertNil(unchanged?.delivery.receipt)
    }

    // Break: callers bypass Send eligibility and start delivery for a Note with corrupt local audio.
    func testLocalAudioErrorRejectsAttemptStart() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let note = try await h.store.saveFinalized(h.recording())
        try await h.store.recordLocalError(.unreadable, noteID: note.id)
        let attempt = Attempt(noteID: note.id, configurationRevisionID: ConfigurationRevisionID(), device: .iphone,
            endpoint: SanitizedEndpoint(scheme: "https", host: "example.com", path: "/hook"), startedAt: Date())

        do {
            _ = try await h.store.apply(.attemptStarted(attempt), to: note.id)
            XCTFail("Corrupt audio started delivery")
        } catch WhimStoreError.notEligible { }
    }

    // Break: a delivered Note keeps the Lock Screen-compatible unsent protection class.
    func testDeliveredAudioMovesToStrictProtection() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let durability = RecordingDurability()
        let files = try AudioFileStore(root: h.root, durability: durability, closeWriter: { _ in })
        let recording = try h.recording()
        try writeAudioFixture(to: files.temporaryURL(for: recording.recordingSessionID))
        let note = try await files.finalize(recording, in: h.store)

        try files.makeDeliveredProtectionStrict(noteID: note.id)

        XCTAssertEqual(durability.protectionCalls.last?.path, note.audioURL.path)
        XCTAssertEqual(durability.protectionCalls.last?.protection, "delivered")
    }

    // Break: disk-full finalization loses the unfinished session or inserts a nonexistent Note.
    func testDiskFullPreservesSessionAndPropagatesVisibleFailure() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let recording = try h.recording()
        try await h.store.saveRecordingSession(RecordingSession(id: recording.recordingSessionID, noteID: recording.id,
            createdAt: recording.createdAt, source: recording.source))
        let files = try AudioFileStore(root: h.root, durability: DiskFullDurability(), closeWriter: { _ in })
        let temporary = try files.temporaryURL(for: recording.recordingSessionID)
        try writeAudioFixture(to: temporary)
        do { _ = try await files.finalize(recording, in: h.store); XCTFail("Disk full must propagate") }
        catch let error as POSIXError { XCTAssertEqual(error.code, .ENOSPC) }
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        let note = try await reopened.note(id: recording.id)
        let sessions = try await reopened.recordingSessions()
        XCTAssertNil(note)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporary.path))
        XCTAssertEqual(sessions.first?.localError, .storageFull)
    }

    // Break: the database claims finalization before a closed, durable Note-ID audio file exists.
    func testAudioFinalizationMovesPlayableFileBeforeSavingNote() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let recording = try h.recording()
        let files = try AudioFileStore(root: h.root, closeWriter: { _ in })
        let temporary = try files.temporaryURL(for: recording.recordingSessionID)
        try writeAudioFixture(to: temporary)
        let note = try await files.finalize(recording, in: h.store)
        XCTAssertEqual(note.audioURL.lastPathComponent, note.id.rawValue.uuidString + ".m4a")
        XCTAssertEqual(note.audioURL.deletingLastPathComponent().lastPathComponent, "Notes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        XCTAssertGreaterThan(try AVAudioFile(forReading: note.audioURL).length, 0)
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        let persisted = try await reopened.note(id: note.id)
        XCTAssertEqual(persisted?.audioURL, note.audioURL)
    }

    // Break: caller-supplied endpoint query values are copied into persisted Attempts.
    func testAttemptEndpointDropsQueryAndFragmentAtPersistenceBoundary() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let note = try await h.store.saveFinalized(h.recording())
        let attempt = Attempt(noteID: note.id, configurationRevisionID: ConfigurationRevisionID(), device: .iphone,
            endpoint: SanitizedEndpoint(scheme: "https", host: "example.com", path: "/hook?token=PRIVATE#fragment"), startedAt: Date())
        _ = try await h.store.apply(.attemptFailed(AttemptFailure(attempt: attempt, failedAt: Date(), reason: .network)), to: note.id)
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        let persisted = try await reopened.note(id: note.id)
        XCTAssertEqual(persisted?.delivery.failedAttempts.first?.attempt.endpoint.path, "/hook")
    }

    // Break: caller-supplied endpoint query values are copied into persisted Configuration Revisions.
    func testConfigurationRevisionEndpointDropsQueryAndFragmentAtPersistenceBoundary() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let note = try await h.store.saveFinalized(h.recording())
        let revision = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: Date(),
            endpoint: SanitizedEndpoint(scheme: "https", host: "example.com", path: "/hook?token=SECRET#fragment"))

        try await h.store.saveConfigurationRevision(revision)
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        let persisted = try await reopened.configurationRevision(for: note.id)

        XCTAssertEqual(persisted?.endpoint.path, "/hook")
    }

    // Break: an offline import resurrects a deleted Note after process restart.
    func testTombstonePreventsResurrectionAndRetainsEndpointAcknowledgements() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let recording = try h.recording()
        let note = try await h.store.saveFinalized(recording)
        try await h.store.delete(noteID: note.id)
        try await h.store.acknowledgeDeletion(noteID: note.id, endpoint: .iphone)
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        do { _ = try await reopened.saveFinalized(recording); XCTFail("Deleted Note resurrected") }
        catch WhimStoreError.deletedNote { }
        let missing = try await reopened.note(id: note.id)
        let tombstones = try await reopened.deletions()
        XCTAssertNil(missing)
        XCTAssertEqual(tombstones.first?.noteID, note.id)
        XCTAssertEqual(tombstones.first?.acknowledgedEndpoints, [.iphone])
        try await reopened.acknowledgeDeletion(noteID: note.id, endpoint: .appleWatch)
        try await reopened.acknowledgeDeletion(noteID: note.id, endpoint: .appleWatch)
        let acknowledged = try await reopened.deletions()
        XCTAssertEqual(acknowledged.first?.acknowledgedEndpoints.count, 2)
    }

    // Break: transient flags survive restart, or live lease rows disappear from projections.
    func testRuntimeFlagsReconstructFromLeaseRows() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let note = try await h.store.saveFinalized(h.recording())
        let first: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL, now: { Date(timeIntervalSince1970: 100) })
        _ = try await first.acquireLease(.delivery, noteID: note.id, owner: UUID(), until: Date(timeIntervalSince1970: 200))
        let offline = try await first.apply(.connectivityChanged(false), to: note.id)
        XCTAssertFalse(offline.isConnected)
        XCTAssertTrue(offline.hasExecutionLease)
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL, now: { Date(timeIntervalSince1970: 201) })
        let fresh = try await reopened.note(id: note.id)
        XCTAssertTrue(fresh!.delivery.isConnected)
        XCTAssertFalse(fresh!.delivery.hasExecutionLease)
    }

    // Break: independent workers can both hold the same lease, or an expired lease never frees.
    func testLeasesExcludeOtherOwnersAndExpireAcrossInstances() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let note = try await h.store.saveFinalized(h.recording())
        let first: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL, now: { Date(timeIntervalSince1970: 100) })
        let second: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL, now: { Date(timeIntervalSince1970: 100) })
        let owner1 = UUID(), owner2 = UUID(), expiry = Date(timeIntervalSince1970: 200)
        async let a = first.acquireLease(.delivery, noteID: note.id, owner: owner1, until: expiry)
        async let b = second.acquireLease(.delivery, noteID: note.id, owner: owner2, until: expiry)
        let results = try await [a, b]
        XCTAssertEqual(results.filter { $0 }.count, 1)
        let loser = results[0] ? owner2 : owner1
        try await second.releaseLease(.delivery, noteID: note.id, owner: loser)
        let stillExcluded = try await second.acquireLease(.delivery, noteID: note.id, owner: loser, until: expiry)
        XCTAssertFalse(stillExcluded)
        let expired: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL, now: { Date(timeIntervalSince1970: 201) })
        let acquired = try await expired.acquireLease(.delivery, noteID: note.id, owner: loser, until: Date(timeIntervalSince1970: 300))
        XCTAssertTrue(acquired)
        try await expired.releaseLease(.delivery, noteID: note.id, owner: loser)
        let afterRelease = try await expired.note(id: note.id)
        XCTAssertFalse(afterRelease!.delivery.hasExecutionLease)
    }

    // Break: unsent Notes keep stale configuration when a newer revision is known.
    func testNewestConfigurationSelectedWithoutChangingPriorAttempt() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let note = try await h.store.saveFinalized(h.recording())
        let old = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: Date(timeIntervalSince1970: 10),
            endpoint: SanitizedEndpoint(scheme: "https", host: "old.example.com", path: "/old"))
        let new = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: Date(timeIntervalSince1970: 20),
            endpoint: SanitizedEndpoint(scheme: "https", host: "new.example.com", path: "/new"))
        try await h.store.saveConfigurationRevision(old)
        let attempt = Attempt(noteID: note.id, configurationRevisionID: old.id, device: .appleWatch, endpoint: old.endpoint, startedAt: Date())
        _ = try await h.store.apply(.attemptFailed(AttemptFailure(attempt: attempt, failedAt: Date(), reason: .network)), to: note.id)
        try await h.store.saveConfigurationRevision(new)
        try await h.store.saveConfigurationRevision(old)
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        let selected = try await reopened.configurationRevision(for: note.id)
        let persisted = try await reopened.note(id: note.id)
        XCTAssertEqual(selected?.id, new.id)
        XCTAssertEqual(persisted?.delivery.failedAttempts.first?.attempt.configurationRevisionID, old.id)
        XCTAssertEqual(persisted?.delivery.status, .queued)
    }

    // Break: a late failure or process restart overwrites successful Delivery evidence.
    func testReceiptPrecedenceAndFiltersSurviveReopen() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let note = try await h.store.saveFinalized(h.recording())
        let attempt = Attempt(noteID: note.id, configurationRevisionID: ConfigurationRevisionID(),
            device: .iphone, endpoint: SanitizedEndpoint(scheme: "https", host: "example.com", path: "/hook"), startedAt: Date())
        _ = try await h.store.apply(.attemptStarted(attempt), to: note.id)
        let sending = try await h.store.note(id: note.id)
        XCTAssertEqual(sending?.delivery.status, .sending)
        let receipt = Receipt(attemptID: attempt.id, noteID: note.id, receivedAt: Date(), statusCode: 204)
        _ = try await h.store.apply(.receipt(receipt), to: note.id)
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        _ = try await reopened.apply(.attemptFailed(AttemptFailure(attempt: attempt, failedAt: Date(), reason: .network)), to: note.id)
        _ = try await reopened.apply(.receipt(receipt), to: note.id)
        let sent = try await reopened.note(id: note.id)
        let sentRows = try await reopened.listNotes(filter: .sent)
        let failedRows = try await reopened.listNotes(filter: .failed)
        let queuedRows = try await reopened.listNotes(filter: .queued)
        XCTAssertEqual(sent?.delivery.receipt, receipt)
        XCTAssertEqual(sentRows.map(\.id), [note.id])
        XCTAssertTrue(failedRows.isEmpty)
        XCTAssertTrue(queuedRows.isEmpty)
    }

    // Break: queries return insertion order instead of newest capture first.
    func testTimelineIsNewestFirstAcrossReopen() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let newer = try await h.store.saveFinalized(h.recording(createdAt: Date(timeIntervalSince1970: 200)))
        let older = try await h.store.saveFinalized(h.recording())
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: h.databaseURL)
        let rows = try await reopened.listNotes(filter: .all)
        XCTAssertEqual(rows.map(\.id), [newer.id, older.id])
    }

    // Break: finalized metadata is lost when the process opens a fresh store.
    func testFinalizedNoteSurvivesStoreReopen() async throws {
        let h = try PersistenceHarness()
        defer { h.remove() }
        let saved = try await h.store.saveFinalized(h.recording())
        let reopened = try SQLiteWhimStore.open(at: h.databaseURL)
        let note = try await reopened.note(id: saved.id)
        XCTAssertEqual(note?.id, saved.id)
        XCTAssertEqual(note?.title, "A fixture recording")
        XCTAssertEqual(note?.delivery.status, .setupRequired)
    }
}

struct PersistenceHarness {
    let root: URL
    let databaseURL: URL
    let store: any WhimStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        databaseURL = root.appendingPathComponent("whim.sqlite")
        store = try SQLiteWhimStore.open(at: databaseURL)
    }

    func recording(id: NoteID = NoteID(), createdAt: Date = Date(timeIntervalSince1970: 100)) throws -> FinalizedRecording {
        let audio = root.appendingPathComponent(id.rawValue.uuidString + ".m4a")
        try Data([0, 1, 2, 3]).write(to: audio)
        return FinalizedRecording(id: id, recordingSessionID: RecordingSessionID(),
            title: "A fixture recording", titleSource: .timestamp, createdAt: createdAt,
            duration: 2, source: .iphone, captureOutcome: .completed, requiresReview: false, audioURL: audio)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

func writeAudioFixture(to url: URL) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let writer = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
    ])
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
    buffer.frameLength = 1_600
    buffer.floatChannelData![0].initialize(repeating: 0, count: 1_600)
    try writer.write(from: buffer)
}

struct DiskFullDurability: FileDurability {
    func synchronizeFile(at url: URL) throws { throw POSIXError(.ENOSPC) }
    func protect(_ url: URL, as protection: AudioProtection) throws { }
    func synchronizeDirectory(at url: URL) throws { }
}

final class RecordingDurability: FileDurability, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(path: String, protection: String)] = []

    var protectionCalls: [(path: String, protection: String)] {
        lock.withLock { calls }
    }

    func synchronizeFile(at url: URL) throws { }

    func protect(_ url: URL, as protection: AudioProtection) throws {
        let label: String
        switch protection {
        case .unsent: label = "unsent"
        case .delivered: label = "delivered"
        }
        lock.withLock { calls.append((url.path, label)) }
    }

    func synchronizeDirectory(at url: URL) throws { }
}
