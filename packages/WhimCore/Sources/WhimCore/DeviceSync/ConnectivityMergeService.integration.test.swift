import Foundation
import XCTest
@testable import WhimCore

final class ConnectivityMergeTests: XCTestCase {
    func testDeletionAndResetReportPendingUntilPeerAcknowledgesAppliedState() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let transport = SyncTransport(); transport.active = true
        let merge = try ConnectivityMergeService(store: h.store, files: h.files, databaseURL: h.root.appendingPathComponent("whim.sqlite"),
            root: h.root.appendingPathComponent("Peer"), device: .iphone, transport: transport)
        let id = NoteID()
        _ = try await merge.apply(.init(payload: .deletion(id)))
        try await merge.flush()
        XCTAssertTrue(transport.sent.contains { if case .acknowledgement(.deletion(id, .iphone)) = $0.payload { true } else { false } })
        _ = try await merge.apply(.init(payload: .acknowledgement(.deletion(id, .appleWatch))))
        let tombstone = try await h.store.deletions().first
        XCTAssertEqual(Set(tombstone?.acknowledgedEndpoints ?? []), Set([.iphone, .appleWatch]))
        let reset = try await merge.prepareReset()
        _ = try await merge.apply(reset)
        try await merge.flush()
        let pending = try await merge.status()
        XCTAssertEqual(pending.resetState, "pending")
        _ = try await merge.apply(.init(generation: reset.generation, payload: .acknowledgement(.reset(.appleWatch))))
        let complete = try await merge.status()
        XCTAssertEqual(complete.resetState, "synchronized")
        XCTAssertNotNil(complete.lastSynchronizedAt)
    }

    func testDelegateInboxSurvivesProcessExitBeforeActorHandoffAndRedactsAttemptQuery() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Captured before return",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        let envelope = ConnectivityEnvelope(payload: .noteMetadata(metadata))
        let inbox = try ConnectivityInbox(databaseURL: h.root.appendingPathComponent("whim.sqlite"))
        try inbox.capture(envelope.encoded())
        let attempt = Attempt(noteID: metadata.id, configurationRevisionID: ConfigurationRevisionID(), device: .appleWatch,
            endpoint: .init(scheme: "https", host: "example.com", path: "/receive?private-query"), startedAt: Date())
        try inbox.capture(ConnectivityEnvelope(payload: .attempt(.failed(.init(attempt: attempt,
            failedAt: Date(), reason: .network, responseExcerpt: "private-response")))).encoded())
        let restarted = try h.merge()
        try await restarted.recover()
        _ = try await restarted.receiveFile(at: h.fixture, metadata: envelope)
        let note = try await h.store.listNotes(filter: .all).first
        XCTAssertEqual(note?.id, metadata.id)
        for file in try FileManager.default.contentsOfDirectory(at: h.root, includingPropertiesForKeys: nil)
            where file.lastPathComponent.hasPrefix("whim.sqlite") {
            let bytes = try Data(contentsOf: file)
            XCTAssertNil(bytes.range(of: Data("private-query".utf8)))
            XCTAssertNil(bytes.range(of: Data("private-response".utf8)))
        }
        try inbox.capture(ConnectivityEnvelope(generation: .init(counter: 100, origin: UUID()), payload: .reset).encoded())
        try await h.merge().recover()
        let afterReset = try await h.store.listNotes(filter: .all)
        XCTAssertTrue(afterReset.isEmpty, "A reset captured before process exit is applied on receiver launch")
    }

    func testFailedPeerCaptureReplaysSameMessageUntilDurableAcknowledgementWithoutAckLoops() async throws {
        let source = try SyncHarness(); defer { source.remove() }
        let receiver = try SyncHarness(); defer { receiver.remove() }
        let sourceTransport = SyncTransport(); sourceTransport.active = true
        let receiverTransport = SyncTransport(); receiverTransport.active = true
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Replay",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        let envelope = ConnectivityEnvelope(payload: .noteMetadata(metadata))
        let importer = try source.merge()
        _ = try await importer.apply(envelope)
        _ = try await importer.receiveFile(at: source.fixture, metadata: envelope)
        func sender() throws -> ConnectivityMergeService {
            try .init(store: source.store, files: source.files, databaseURL: source.root.appendingPathComponent("whim.sqlite"),
                root: source.root.appendingPathComponent("Peer"), device: .appleWatch, transport: sourceTransport)
        }
        let destination = try ConnectivityMergeService(store: receiver.store, files: receiver.files,
            databaseURL: receiver.root.appendingPathComponent("whim.sqlite"), root: receiver.root.appendingPathComponent("Peer"),
            device: .iphone, transport: receiverTransport)
        try await sender().queueNote(metadata.id)
        let fileEnvelope = try XCTUnwrap(sourceTransport.fileEnvelopes.first)
        do {
            _ = try await destination.receiveFile(at: receiver.root.appendingPathComponent("missing.m4a"), metadata: fileEnvelope)
            XCTFail("Missing OS file must not be acknowledged")
        } catch {}
        try await destination.flush()
        XCTAssertTrue(receiverTransport.sent.isEmpty)
        try await sender().activated()
        XCTAssertEqual(sourceTransport.fileEnvelopes.map(\.messageID), [fileEnvelope.messageID, fileEnvelope.messageID])
        _ = try await destination.receiveFile(at: source.fixture, metadata: fileEnvelope)
        try await destination.flush()
        let expected = ConnectivityEnvelope.Payload.acknowledgement(.durable(fileEnvelope.messageID))
        let acknowledgement = try XCTUnwrap(receiverTransport.sent.first { $0.payload == expected })
        _ = try await sender().apply(acknowledgement)
        _ = try await sender().apply(acknowledgement)
        try await sender().activated()
        XCTAssertEqual(sourceTransport.fileEnvelopes.count, 2)
        XCTAssertFalse(sourceTransport.sent.contains { $0.payload == .acknowledgement(.durable(acknowledgement.messageID)) })
    }

    func testPendingResetCannotStampAnOldNoteWithTheNewGeneration() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Old Note",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        let importer = try h.merge()
        let envelope = ConnectivityEnvelope(payload: .noteMetadata(metadata))
        _ = try await importer.apply(envelope)
        _ = try await importer.receiveFile(at: h.fixture, metadata: envelope)
        let transport = SyncTransport(); transport.active = true
        let merge = try ConnectivityMergeService(store: h.store, files: h.files, databaseURL: h.root.appendingPathComponent("whim.sqlite"),
            root: h.root.appendingPathComponent("Peer"), device: .appleWatch, transport: transport)
        _ = try await merge.prepareReset()
        try await merge.queueNote(metadata.id)
        XCTAssertTrue(transport.files.isEmpty)
        XCTAssertFalse(transport.sent.contains { if case .noteMetadata = $0.payload { true } else { false } })
    }

    func testFinalizedWatchNoteQueuesDurableMetadataAndFileWithoutReachability() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Watch Note",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        let envelope = ConnectivityEnvelope(payload: .noteMetadata(metadata))
        let importer = try h.merge()
        _ = try await importer.apply(envelope)
        _ = try await importer.receiveFile(at: h.fixture, metadata: envelope)
        let transport = SyncTransport()
        let sender = try ConnectivityMergeService(store: h.store, files: h.files,
            databaseURL: h.root.appendingPathComponent("whim.sqlite"), root: h.root.appendingPathComponent("Peer"),
            device: .appleWatch, transport: transport)
        try await sender.queueNote(metadata.id)
        XCTAssertTrue(transport.sent.isEmpty)
        transport.active = true
        let restarted = try ConnectivityMergeService(store: h.store, files: h.files,
            databaseURL: h.root.appendingPathComponent("whim.sqlite"), root: h.root.appendingPathComponent("Peer"),
            device: .appleWatch, transport: transport)
        try await restarted.flush()
        XCTAssertEqual(transport.files.count, 1)
        XCTAssertTrue(transport.sent.contains { if case .noteMetadata = $0.payload { true } else { false } })
        try await restarted.queueNote(metadata.id)
        try await restarted.flush()
        XCTAssertEqual(transport.files.count, 1, "Durably submitted duplicate snapshot is not requeued")
    }

    func testNewestConfigurationUsesKeychainAndNeverPersistsSecretEnvelope() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let keychain = SyncCredentials()
        let transport = SyncTransport(); transport.active = true
        let merge = try ConnectivityMergeService(store: h.store, files: h.files,
            databaseURL: h.root.appendingPathComponent("whim.sqlite"), root: h.root.appendingPathComponent("Peer"),
            device: .appleWatch, credentials: keychain, transport: transport)
        let old = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: Date(timeIntervalSince1970: 100),
            endpoint: .init(scheme: "https", host: "old.example.com", path: "/"))
        let newest = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: Date(timeIntervalSince1970: 200),
            endpoint: .init(scheme: "https", host: "new.example.com", path: "/"))
        let secrets = StoredWebhookCredentials(endpoint: URL(string: "https://new.example.com/?key=private-query")!,
            bearerToken: "private-bearer", hmacSecret: "private-hmac", customHeaders: [])
        try await merge.receiveConfiguration(.init(payload: .configuration(newest)), credentials: secrets)
        try await merge.receiveConfiguration(.init(payload: .configuration(old)), credentials: secrets)
        let revision = try await h.store.latestConfigurationRevision()
        XCTAssertEqual(revision, newest)
        let saved = await keychain.credentials(for: newest.id)
        XCTAssertEqual(saved, secrets)
        try await merge.flush()
        let expected = ConnectivityEnvelope.Payload.acknowledgement(.configuration(newest.id))
        XCTAssertTrue(transport.sent.map(\.payload).contains(expected))
        // Inspect bytes only for the security boundary, never as a projection assertion.
        for file in try FileManager.default.contentsOfDirectory(at: h.root, includingPropertiesForKeys: nil)
            where file.lastPathComponent.hasPrefix("whim.sqlite") {
            let bytes = try Data(contentsOf: file)
            for secret in ["private-query", "private-bearer", "private-hmac"] {
                XCTAssertNil(bytes.range(of: Data(secret.utf8)))
            }
        }
    }

    func testDeletionAndResetBarriersSurviveRestartAndRejectStaleData() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let old = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Before reset",
            titleSource: .timestamp, createdAt: Date(timeIntervalSince1970: 100), duration: 1,
            source: .appleWatch, captureOutcome: .completed, requiresReview: false)
        let metadata = ConnectivityEnvelope(payload: .noteMetadata(old))
        let first = try h.merge()
        _ = try await first.apply(.init(payload: .deletion(old.id)))
        _ = try await first.receiveFile(at: h.fixture, metadata: metadata)
        _ = try await h.merge().apply(metadata)
        let deleted = try await h.store.listNotes(filter: .all)
        XCTAssertTrue(deleted.isEmpty)
        let tombstones = try await h.store.deletions()
        XCTAssertEqual(tombstones.first?.acknowledgedEndpoints, [.iphone])
        let reset = try await first.prepareReset(now: Date(timeIntervalSince1970: 200))
        _ = try await h.merge().apply(reset) // restart with a prepared, uncompleted reset
        _ = try await h.merge().apply(metadata)
        _ = try await h.merge().receiveFile(at: h.fixture, metadata: metadata)
        let stale = try await h.store.listNotes(filter: .all)
        XCTAssertTrue(stale.isEmpty)
        let current = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "After reset",
            titleSource: .timestamp, createdAt: Date(timeIntervalSince1970: 201), duration: 1,
            source: .appleWatch, captureOutcome: .completed, requiresReview: false)
        let fresh = ConnectivityEnvelope(generation: reset.generation, payload: .noteMetadata(current))
        _ = try await h.merge().apply(fresh)
        _ = try await h.merge().receiveFile(at: h.fixture, metadata: fresh)
        _ = try await h.merge().apply(reset)
        let retained = try await h.store.listNotes(filter: .all)
        XCTAssertEqual(retained.map(\.id), [current.id], "A duplicate completed reset cannot erase new captures")
        let rollback = try await h.merge().prepareReset(now: Date(timeIntervalSince1970: 1))
        XCTAssertGreaterThan(rollback.generation, reset.generation)
    }

    func testUnknownHigherDataGenerationDoesNotAuthorizeErasure() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Future",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        let message = ConnectivityEnvelope(generation: .init(counter: 9, origin: UUID()), payload: .noteMetadata(metadata))
        _ = try await h.merge().apply(message)
        _ = try await h.merge().receiveFile(at: h.fixture, metadata: message)
        let notes = try await h.store.listNotes(filter: .all)
        XCTAssertTrue(notes.isEmpty)
        let generation = try await h.merge().generation()
        XCTAssertEqual(generation, .initial)
        _ = try await h.merge().apply(.init(generation: message.generation, payload: .reset))
        let afterReset = try await h.store.listNotes(filter: .all)
        XCTAssertEqual(afterReset.map(\.id), [metadata.id], "Higher-generation file is deferred until its reset is authenticated")
    }

    func testFailuresReceiptsAndTitleConvergeAcrossAllMeaningfulOrders() async throws {
        let id = NoteID()
        let metadata = NoteTransfer(id: id, recordingSessionID: RecordingSessionID(), title: "Watch recording",
            titleSource: .timestamp, createdAt: Date(timeIntervalSince1970: 100), duration: 1,
            source: .appleWatch, captureOutcome: .completed, requiresReview: false)
        let watch = Attempt(noteID: id, configurationRevisionID: ConfigurationRevisionID(), device: .appleWatch,
            endpoint: .init(scheme: "https", host: "old.example.com", path: "/"), startedAt: Date(timeIntervalSince1970: 101))
        let phone = Attempt(noteID: id, configurationRevisionID: ConfigurationRevisionID(), device: .iphone,
            endpoint: .init(scheme: "https", host: "new.example.com", path: "/"), startedAt: Date(timeIntervalSince1970: 102))
        let early = Receipt(attemptID: watch.id, noteID: id, receivedAt: Date(timeIntervalSince1970: 103), statusCode: 201)
        let late = Receipt(attemptID: phone.id, noteID: id, receivedAt: Date(timeIntervalSince1970: 104), statusCode: 204)
        let messages: [ConnectivityEnvelope] = [
            .init(payload: .noteMetadata(metadata)),
            .init(payload: .attempt(.failed(.init(attempt: watch, failedAt: Date(timeIntervalSince1970: 105), reason: .network)))),
            .init(payload: .attempt(.failed(.init(attempt: phone, failedAt: Date(timeIntervalSince1970: 106), reason: .httpStatus(400))))),
            .init(payload: .receipt(late)), .init(payload: .receipt(early)),
            .init(payload: .title(.init(noteID: id, title: "An idea from the Watch", source: .transcription)))
        ]
        // Each event occurs before and after every other event, including duplicates and file handoff.
        for rotation in messages.indices {
            for reversed in [false, true] {
                let h = try SyncHarness(); defer { h.remove() }
                let merge = try h.merge()
                let order = Array(messages[rotation...] + messages[..<rotation])
                _ = try await merge.receiveFile(at: h.fixture, metadata: messages[0])
                for message in reversed ? order.reversed().map({ $0 }) : order {
                    _ = try await merge.apply(message)
                    _ = try await h.merge().apply(message)
                }
                let notes = try await h.store.listNotes(filter: .all)
                XCTAssertEqual(notes.first?.title, "An idea from the Watch")
                XCTAssertEqual(notes.first?.status, .sent)
                let note = try await h.store.note(id: id)
                XCTAssertEqual(note?.delivery.receipt, early, "Earliest success defines retention, independent of arrival")
                let attempts = try await h.store.deliveryAttempts(noteID: id)
                XCTAssertEqual(Set(attempts.map(\.id)), Set([watch.id, phone.id]))
            }
        }
    }

    func testFileAndMetadataImportInEitherOrderAcrossRestart() async throws {
        let noteID = NoteID()
        let metadata = NoteTransfer(id: noteID, recordingSessionID: RecordingSessionID(),
            title: "Watch recording", titleSource: .timestamp, createdAt: Date(timeIntervalSince1970: 100),
            duration: 1, source: .appleWatch, captureOutcome: .completed, requiresReview: false)
        var projections: [NoteProjection] = []
        for fileFirst in [false, true] {
            let harness = try SyncHarness()
            defer { harness.remove() }
            let first = try harness.merge()
            if fileFirst { _ = try await first.receiveFile(at: harness.fixture, metadata: .init(payload: .noteMetadata(metadata))) }
            else { _ = try await first.apply(.init(payload: .noteMetadata(metadata))) }
            let premature = try await harness.store.listNotes(filter: .all)
            XCTAssertTrue(premature.isEmpty, "Neither metadata nor an unpaired file claims durable Note audio")
            let restarted = try harness.merge()
            if fileFirst { _ = try await restarted.apply(.init(payload: .noteMetadata(metadata))) }
            else { _ = try await restarted.receiveFile(at: harness.fixture, metadata: .init(payload: .noteMetadata(metadata))) }
            _ = try await restarted.apply(.init(payload: .noteMetadata(metadata)))
            let notes = try await harness.store.listNotes(filter: .all)
            XCTAssertEqual(notes.count, 1)
            projections += notes
            let note = try await harness.store.note(id: noteID)
            XCTAssertNil(harness.files.audioError(at: try XCTUnwrap(note).audioURL))
        }
        XCTAssertEqual(projections[0], projections[1])
    }
}

private struct SyncHarness {
    let root: URL
    let store: SQLiteWhimStore
    let files: AudioFileStore
    var fixture: URL { Bundle.module.url(forResource: "configuration-test-fixture", withExtension: "m4a", subdirectory: "Fixtures")! }
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = try .open(at: root.appendingPathComponent("whim.sqlite"))
        files = try .init(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
    }
    func merge() throws -> ConnectivityMergeService {
        try .init(store: store, files: files, databaseURL: root.appendingPathComponent("whim.sqlite"), root: root.appendingPathComponent("Peer"), device: .iphone)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private actor SyncCredentials: CredentialStore {
    var values: [ConfigurationRevisionID: StoredWebhookCredentials] = [:]
    func save(_ value: StoredWebhookCredentials, for id: ConfigurationRevisionID) { values[id] = value }
    func credentials(for id: ConfigurationRevisionID) -> StoredWebhookCredentials? { values[id] }
    func remove(for id: ConfigurationRevisionID) { values[id] = nil }
    func removeAll() { values = [:] }
}

private final class SyncTransport: PeerTransport, @unchecked Sendable {
    var active = false
    var sent: [ConnectivityEnvelope] = []
    var files: [URL] = []
    var fileEnvelopes: [ConnectivityEnvelope] = []
    var isAvailable: Bool { true }
    var isActivated: Bool { active }
    func activate(receive: @escaping @Sendable (PeerEvent) -> Void) {}
    func transfer(_ envelope: ConnectivityEnvelope) throws { sent.append(envelope) }
    func transferFile(at url: URL, metadata: ConnectivityEnvelope) throws { files.append(url); fileEnvelopes.append(metadata) }
    func updateContext(_ envelope: ConnectivityEnvelope, credentials: StoredWebhookCredentials?) throws {}
}
