import Foundation
import XCTest
import GRDB
@testable import WhimCore

final class ConnectivityMergeTests: XCTestCase {
    func testManualRetrySupersedesAnOfflineRequestWithoutRecordingAFailure() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let transport = SyncTransport(); transport.active = true; transport.available = false
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Waiting for Watch",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        let merge = try h.merge(transport: transport)
        _ = try await merge.apply(.init(payload: .noteMetadata(metadata)))
        try await merge.retryAudio(metadata.id)
        let waiting = try await h.store.note(id: metadata.id)
        XCTAssertEqual(waiting?.audioSynchronizationRetries?.map(\.outcome), [.waiting])
        try await merge.recover()
        try await merge.retryAudio(metadata.id)
        let replaced = try await h.store.note(id: metadata.id)
        XCTAssertEqual(replaced?.audioSynchronizationRetries?.map(\.outcome), [.superseded, .waiting])
        XCTAssertEqual(replaced?.audioSynchronization?.transferCount, 1)
    }

    func testLegacyAcceptedTransferDoesNotBecomeANewRetentionHoldOnUpgrade() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let transport = SyncTransport(); transport.active = true
        let id = NoteID()
        let source = h.files.audioURL(for: id)
        try FileManager.default.copyItem(at: h.fixture, to: source)
        _ = try await h.store.saveFinalized(.init(id: id, recordingSessionID: RecordingSessionID(),
            title: "Already accepted", titleSource: .timestamp, createdAt: Date(), duration: 1,
            source: .appleWatch, captureOutcome: .completed, requiresReview: false, audioURL: source))
        let prior = try h.merge(transport: transport, device: .appleWatch)
        try await prior.queueNote(id)
        let accepted = try XCTUnwrap(transport.fileEnvelopes.first)
        _ = try await prior.apply(.init(payload: .acknowledgement(.durable(accepted.messageID))))
        // Older builds persist accepted file transfers but have no independent hold table.
        let legacy = try DatabaseQueue(path: h.root.appendingPathComponent("whim.sqlite").path)
        try await legacy.write { db in try db.execute(sql: "DROP TABLE peer_audio_handoffs") }
        let upgraded = try h.merge(transport: transport, device: .appleWatch)
        try await upgraded.queueNote(id)
        let pending = try await upgraded.pendingAudioNoteIDs()
        XCTAssertTrue(pending.isEmpty, "Upgrading cannot undo an already accepted handoff")
    }

    func testUnreadableSourceHandoffHoldIsRemovedByDeleteOrReset() async throws {
        for reset in [false, true] {
            let h = try SyncHarness(); defer { h.remove() }
            let id = NoteID()
            let source = h.files.audioURL(for: id)
            try Data("unreadable source".utf8).write(to: source)
            _ = try await h.store.saveFinalized(.init(id: id, recordingSessionID: RecordingSessionID(),
                title: "Pending handoff", titleSource: .timestamp, createdAt: Date(), duration: 1,
                source: .appleWatch, captureOutcome: .completed, requiresReview: false, audioURL: source))
            let watch = try h.merge(device: .appleWatch)
            try await watch.queueNote(id)
            let before = try await watch.pendingAudioNoteIDs()
            XCTAssertEqual(before, [id])
            if reset { _ = try await watch.apply(watch.prepareReset()) }
            else { try await h.store.delete(noteID: id); try await watch.queueDeletion(id) }
            let after = try await watch.pendingAudioNoteIDs()
            XCTAssertTrue(after.isEmpty)
        }
    }

    func testSuspendedMetadataSnapshotCannotRetireANewManualRequest() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let transport = SyncTransport(); transport.active = true; transport.available = false
        let commands = try h.merge(transport: transport)
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Concurrent metadata",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        _ = try await h.store.savePendingPeerNote(metadata.finalized(audioURL: h.files.audioURL(for: metadata.id)))
        let paused = expectation(description: "Another process suspends after its real SQLite snapshot")
        let scheduling = PausingSynchronizationStore(base: h.store, paused: paused)
        defer { Task { await scheduling.resume() } }
        let incoming = try ConnectivityMergeService(store: scheduling, files: h.files, databaseURL: h.root.appendingPathComponent("whim.sqlite"),
            root: h.root.appendingPathComponent("Peer"), device: .iphone, transport: transport)
        let importTask = Task { try await incoming.apply(.init(payload: .noteMetadata(metadata))) }
        await fulfillment(of: [paused], timeout: 2)
        try await commands.retryAudio(metadata.id)
        await scheduling.resume()
        _ = try await importTask.value
        transport.available = true
        try await commands.activated()
        XCTAssertEqual(transport.audioRequests.count, 1, "A stale SQLite snapshot cannot retire a newer request")
    }

    func testValidResendRepairsARejectedFileBeforeOrdinaryMetadataArrives() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let transport = SyncTransport(); transport.active = true
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "File before control",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        let corrupted = h.root.appendingPathComponent("corrupt.m4a")
        try Data("broken".utf8).write(to: corrupted)
        let merge = try h.merge(transport: transport)
        _ = try await merge.receiveFile(at: corrupted, metadata: .init(payload: .noteMetadata(metadata)))
        try await merge.flush()
        let request = try XCTUnwrap(transport.audioRequests.last)
        let reply = ConnectivityEnvelope(payload: .noteMetadata(.init(id: metadata.id,
            recordingSessionID: metadata.recordingSessionID, title: metadata.title, titleSource: metadata.titleSource,
            createdAt: metadata.createdAt, duration: metadata.duration, source: metadata.source,
            captureOutcome: metadata.captureOutcome, requiresReview: false, audioRequestID: request.requestID)))
        _ = try await merge.receiveFile(at: h.fixture, metadata: reply)
        let repaired = try await h.store.listNotes(filter: .all).first
        XCTAssertNil(repaired?.audioSynchronization)
        XCTAssertTrue(try XCTUnwrap(repaired).hasLocalAudio)
        _ = try await merge.apply(.init(payload: .noteMetadata(metadata)))
        let later = try await h.store.listNotes(filter: .all)
        XCTAssertEqual(later.count, 1)
        XCTAssertEqual(later.first?.id, metadata.id)
    }

    func testRecoveringRejectedFileNeverAcknowledgesAudioOrReleasesWatchSource() async throws {
        let phone = try SyncHarness(); defer { phone.remove() }
        let watch = try SyncHarness(); defer { watch.remove() }
        let outgoing = SyncTransport(); outgoing.active = true
        let incoming = SyncTransport(); incoming.active = true
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Keep the source",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        let source = watch.files.audioURL(for: metadata.id)
        try FileManager.default.copyItem(at: watch.fixture, to: source)
        _ = try await watch.store.saveFinalized(metadata.finalized(audioURL: source))
        let sender = try watch.merge(transport: outgoing, device: .appleWatch)
        try await sender.queueNote(metadata.id)
        let fileEnvelope = try XCTUnwrap(outgoing.fileEnvelopes.first)
        let corrupted = phone.root.appendingPathComponent("corrupt.m4a")
        try Data("broken audio".utf8).write(to: corrupted)
        _ = try await phone.merge(transport: incoming).receiveFile(at: corrupted, metadata: fileEnvelope)
        let restarted = try phone.merge(transport: incoming)
        try await restarted.recover()
        try await restarted.flush()
        XCTAssertFalse(incoming.sent.contains { $0.payload == .acknowledgement(.durable(fileEnvelope.messageID)) })
        for message in incoming.sent {
            if case .acknowledgement = message.payload { _ = try await sender.apply(message) }
        }
        let held = try await sender.pendingAudioNoteIDs()
        XCTAssertEqual(held, [metadata.id])
        let note = try await phone.store.note(id: metadata.id)
        XCTAssertFalse(try XCTUnwrap(note).isDeliveryEligible)
    }

    func testInitialUnavailableWatchSourceStartsBoundedRepairEvenWhenFailurePrecedesMetadata() async throws {
        for failureFirst in [false, true] {
            let phone = try SyncHarness(); defer { phone.remove() }
            let watch = try SyncHarness(); defer { watch.remove() }
            let outgoing = SyncTransport(); outgoing.active = true
            let incoming = SyncTransport(); incoming.active = true
            let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Source went missing",
                titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
                captureOutcome: .completed, requiresReview: false)
            let source = watch.files.audioURL(for: metadata.id)
            try FileManager.default.copyItem(at: watch.fixture, to: source)
            _ = try await watch.store.saveFinalized(metadata.finalized(audioURL: source))
            try FileManager.default.removeItem(at: source)
            try await watch.merge(transport: outgoing, device: .appleWatch).queueNote(metadata.id)
            let failure = outgoing.sent.first { if case .audioUnavailable = $0.payload { true } else { false } }
            XCTAssertNotNil(failure, "Initial handoff reports unavailable audio rather than waiting indefinitely")
            guard let failure else { continue }
            let control = try XCTUnwrap(outgoing.sent.first { if case .noteMetadata = $0.payload { true } else { false } })
            let receiver = try phone.merge(transport: incoming)
            for message in failureFirst ? [failure, control] : [control, failure] { _ = try await receiver.apply(message) }
            try await receiver.flush()
            let pending = try await phone.store.note(id: metadata.id)
            XCTAssertEqual(pending?.audioSynchronization?.status, .retrying)
            XCTAssertEqual(pending?.audioSynchronization?.transferCount, 2)
            XCTAssertEqual(incoming.audioRequests.count, 1)
        }
    }

    func testUnavailableWatchAudioRespondsAndExhaustsThreeTransfersWhileOfflineDoesNot() async throws {
        for missing in [false, true] {
            let phone = try SyncHarness(); defer { phone.remove() }
            let watch = try SyncHarness(); defer { watch.remove() }
            let phoneTransport = SyncTransport(); phoneTransport.available = false
            let watchTransport = SyncTransport(); watchTransport.active = true
            let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Unavailable source",
                titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
                captureOutcome: .completed, requiresReview: false)
            let source = watch.files.audioURL(for: metadata.id)
            try FileManager.default.copyItem(at: watch.fixture, to: source)
            _ = try await watch.store.saveFinalized(metadata.finalized(audioURL: source))
            if missing { try FileManager.default.removeItem(at: source) } else { try watch.truncate(source) }
            let sender = try watch.merge(transport: watchTransport, device: .appleWatch)
            let receiver = try phone.merge(transport: phoneTransport)
            _ = try await receiver.apply(.init(payload: .noteMetadata(metadata)))
            try await receiver.retryAudio(metadata.id)
            try await receiver.recover()
            try await receiver.activated()
            let offline = try await phone.store.note(id: metadata.id)
            XCTAssertEqual(offline?.audioSynchronization?.transferCount, 1)
            XCTAssertTrue(phoneTransport.audioRequests.isEmpty)

            phoneTransport.active = true; phoneTransport.available = true
            try await receiver.activated()
            var lastUnavailable: ConnectivityEnvelope?
            for _ in 1...3 {
                let request = try XCTUnwrap(phoneTransport.sent.last { if case .audioRequest = $0.payload { true } else { false } })
                _ = try await sender.apply(request)
                try await sender.flush()
                let reply = try XCTUnwrap(watchTransport.sent.last { if case .audioUnavailable = $0.payload { true } else { false } })
                guard case .audioUnavailable(let unavailable) = reply.payload else { return XCTFail("Expected unavailable response") }
                XCTAssertEqual(unavailable.requestID, request.messageID)
                _ = try await receiver.apply(reply)
                try await receiver.flush()
                lastUnavailable = reply
            }
            let failed = try await phone.store.note(id: metadata.id)
            XCTAssertEqual(failed?.audioSynchronization?.status, .failed)
            XCTAssertEqual(failed?.audioSynchronization?.transferCount, 3)
            XCTAssertEqual(phoneTransport.audioRequests.count, 3, "Manual sync starts a fresh three-transfer cycle")
            XCTAssertTrue(watchTransport.files.isEmpty)

            try await receiver.retryAudio(metadata.id)
            _ = try await receiver.apply(.init(payload: try XCTUnwrap(lastUnavailable).payload))
            let fresh = try await phone.store.note(id: metadata.id)
            XCTAssertEqual(fresh?.audioSynchronization?.status, .retrying)
            XCTAssertEqual(fresh?.audioSynchronization?.transferCount, 1, "Old-cycle replies cannot consume a fresh cycle")
        }
    }

    func testConcurrentDuplicateFailuresAdvanceOnlyOneSynchronizationRetry() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Concurrent replies",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        _ = try await h.store.savePendingPeerNote(metadata.finalized(audioURL: h.files.audioURL(for: metadata.id)))
        var synchronization = AudioSynchronization(status: .retrying, transferCount: 2)
        let requestID = UUID(); synchronization.requestID = requestID
        try await h.store.setAudioSynchronization(synchronization, noteID: metadata.id)
        let transport = SyncTransport(); transport.active = true
        let merge = try h.merge(transport: transport)
        let reply = ConnectivityEnvelope(payload: .audioUnavailable(.init(noteID: metadata.id, requestID: requestID)))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 { group.addTask { _ = try await merge.apply(reply) } }
            try await group.waitForAll()
        }
        try await merge.flush()
        let note = try await h.store.note(id: metadata.id)
        XCTAssertEqual(note?.audioSynchronization?.transferCount, 3)
        XCTAssertEqual(transport.audioRequests.count, 1, "Duplicate concurrent replies cannot create competing resends")
    }

    func testWatchResendsRequestedAudioAndReleasesHandoffOnlyAfterValidAcceptance() async throws {
        let phone = try SyncHarness(); defer { phone.remove() }
        let watch = try SyncHarness(); defer { watch.remove() }
        let phoneTransport = SyncTransport(); phoneTransport.active = true
        let watchTransport = SyncTransport(); watchTransport.active = true
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Repair me",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        let source = watch.files.audioURL(for: metadata.id)
        try FileManager.default.copyItem(at: watch.fixture, to: source)
        _ = try await watch.store.saveFinalized(metadata.finalized(audioURL: source))
        let sender = try watch.merge(transport: watchTransport, device: .appleWatch)
        let receiver = try phone.merge(transport: phoneTransport)
        try await sender.queueNote(metadata.id)
        let initial = try XCTUnwrap(watchTransport.fileEnvelopes.first)
        _ = try await receiver.apply(.init(payload: .noteMetadata(metadata)))
        let corrupt = phone.root.appendingPathComponent("corrupt.m4a")
        try Data("broken".utf8).write(to: corrupt)
        _ = try await receiver.receiveFile(at: corrupt, metadata: initial)
        try await receiver.flush()
        let held = try await sender.pendingAudioNoteIDs()
        XCTAssertEqual(held, [metadata.id], "Corrupt audio is never acknowledged as a durable handoff")

        let request = try XCTUnwrap(phoneTransport.sent.last { if case .audioRequest = $0.payload { true } else { false } })
        _ = try await sender.apply(request)
        try await sender.flush()
        XCTAssertEqual(watchTransport.fileEnvelopes.count, 2)
        let reply = try XCTUnwrap(watchTransport.fileEnvelopes.last)
        guard case .noteMetadata(let response) = reply.payload else { return XCTFail("Expected file metadata") }
        XCTAssertEqual(try XCTUnwrap(response.audioRequestID), request.messageID)
        _ = try await receiver.receiveFile(at: source, metadata: reply)
        try await receiver.flush()
        let repaired = try await phone.store.note(id: metadata.id)
        XCTAssertNil(repaired?.audioSynchronization)
        XCTAssertNil(phone.files.audioError(at: try XCTUnwrap(repaired).audioURL))
        for message in phoneTransport.sent { _ = try await sender.apply(message) }
        let remaining = try await sender.pendingAudioNoteIDs()
        XCTAssertTrue(remaining.isEmpty, "A valid durable copy releases both original and repair transfers")
    }

    func testThreeCorruptTransfersFailSynchronizationWithoutRegressingWatchReceipt() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let transport = SyncTransport(); transport.active = true
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Sent on Watch",
            titleSource: .timestamp, createdAt: Date(), duration: 10, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        let original = ConnectivityEnvelope(payload: .noteMetadata(metadata))
        let corrupted = h.root.appendingPathComponent("corrupt.m4a")
        try Data("not playable audio".utf8).write(to: corrupted)
        let first = try h.merge(transport: transport)
        _ = try await first.apply(original)
        _ = try await first.apply(.init(payload: .receipt(.init(attemptID: AttemptID(), noteID: metadata.id,
            receivedAt: Date(), statusCode: 204))))
        _ = try await first.receiveFile(at: corrupted, metadata: original)
        try await first.flush()

        for retry in 1...2 {
            let request = try XCTUnwrap(transport.audioRequests.last)
            let reply = ConnectivityEnvelope(payload: .noteMetadata(.init(id: metadata.id,
                recordingSessionID: metadata.recordingSessionID, title: metadata.title, titleSource: metadata.titleSource,
                createdAt: metadata.createdAt, duration: metadata.duration, source: metadata.source,
                captureOutcome: metadata.captureOutcome, requiresReview: false, audioRequestID: request.requestID)))
            let restarted = try h.merge(transport: transport)
            _ = try await restarted.receiveFile(at: corrupted, metadata: reply)
            _ = try await restarted.receiveFile(at: corrupted, metadata: reply) // duplicate OS callback
            try await restarted.recover()
            try await restarted.flush()
            let note = try await h.store.note(id: metadata.id)
            XCTAssertEqual(note?.audioSynchronization?.transferCount, min(3, retry + 2))
            XCTAssertEqual(note?.audioSynchronization?.status, retry == 2 ? .failed : .retrying)
            XCTAssertEqual(note?.delivery.status, .sent)
        }
        XCTAssertEqual(transport.audioRequests.count, 2, "The initial corrupt transfer plus two resends exhausts the cycle")
        let exhausted = try h.merge(transport: transport)
        try await exhausted.recover()
        try await exhausted.activated()
        XCTAssertEqual(transport.audioRequests.count, 2, "Relaunch cannot revive exhausted resend requests")
        let summary = try await h.store.listNotes(filter: .all).first
        XCTAssertEqual(summary?.status, .sent)
        XCTAssertFalse(try XCTUnwrap(summary).hasLocalAudio)

        // Retry history is a presentation contract, independent of webhook Attempts.
        func retryOutcomes(_ note: Note) throws -> [String]? {
            let encoded = try JSONEncoder().encode(NoteDetailProjection(note: note))
            let detail = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            return (detail["audioSynchronizationRetries"] as? [[String: Any]])?
                .compactMap { $0["outcome"] as? String }
        }
        let failedNote = try await h.store.note(id: metadata.id)
        XCTAssertEqual(try retryOutcomes(XCTUnwrap(failedNote)), ["failed", "failed"])
        try await exhausted.retryAudio(metadata.id)
        let retryingNote = try await h.store.note(id: metadata.id)
        XCTAssertEqual(try retryOutcomes(XCTUnwrap(retryingNote)), ["failed", "failed", "waiting"])
        let request = try XCTUnwrap(transport.audioRequests.last)
        let validReply = ConnectivityEnvelope(payload: .noteMetadata(.init(id: metadata.id,
            recordingSessionID: metadata.recordingSessionID, title: metadata.title, titleSource: metadata.titleSource,
            createdAt: metadata.createdAt, duration: metadata.duration, source: metadata.source,
            captureOutcome: metadata.captureOutcome, requiresReview: false, audioRequestID: request.requestID)))
        _ = try await exhausted.receiveFile(at: h.fixture, metadata: validReply)
        let reopened = try SQLiteWhimStore.open(at: h.root.appendingPathComponent("whim.sqlite"))
        let repairedNote = try await reopened.note(id: metadata.id)
        XCTAssertNil(repairedNote?.audioSynchronization)
        XCTAssertEqual(try retryOutcomes(XCTUnwrap(repairedNote)), ["failed", "failed", "synced"])
    }

    func testCorruptPendingAudioRequestsRepairWithoutConsumingRetriesOnRecovery() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Interrupted transfer",
            titleSource: .timestamp, createdAt: Date(), duration: 10, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        let envelope = ConnectivityEnvelope(payload: .noteMetadata(metadata))
        _ = try await h.merge().receiveFile(at: h.fixture, metadata: envelope)
        try h.truncate(try h.pendingAudio(metadata.id))
        let transport = SyncTransport(); transport.active = true
        func merge() throws -> ConnectivityMergeService { try h.merge(transport: transport) }
        _ = try await merge().apply(envelope)
        try await merge().recover()
        try await merge().recover()
        try await merge().flush()

        let note = try await h.store.note(id: metadata.id)
        XCTAssertEqual(note?.audioSynchronization?.status, .retrying)
        XCTAssertEqual(note?.audioSynchronization?.transferCount, 2)
        let requests = transport.sent.compactMap { envelope -> AudioTransferRequest? in
            if case .audioRequest(let request) = envelope.payload { return request }; return nil
        }
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.noteID, metadata.id)
    }

    func testWatchMetadataCreatesVisibleUnplayableNoteBeforeAudioArrives() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "On the way",
            titleSource: .timestamp, createdAt: Date(), duration: 10, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        _ = try await h.merge().apply(.init(payload: .noteMetadata(metadata)))

        let notes = try await h.store.listNotes(filter: .all)
        XCTAssertEqual(notes.count, 1, "Watch metadata is visible even before local audio exists")
        guard let summary = notes.first else { return }
        XCTAssertEqual(summary.id, metadata.id)
        XCTAssertFalse(summary.hasLocalAudio)
        let note = try await h.store.note(id: metadata.id)
        XCTAssertFalse(try XCTUnwrap(note).isDeliveryEligible)
        try await h.merge().recover()
        let afterRestart = try await h.store.listNotes(filter: .all)
        XCTAssertEqual(afterRestart, notes)
    }

    func testActivatedSessionWithoutCompanionDefersSyncUntilCompanionIsAvailable() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let credentials = SyncCredentials()
        let configuration = WebhookConfigurationService(store: h.store, credentials: credentials)
        _ = try await configuration.save(.init(endpoint: "https://example.com/whim"))
        let transport = SyncTransport(); transport.active = true; transport.available = false
        func merge() throws -> ConnectivityMergeService {
            try .init(store: h.store, files: h.files, databaseURL: h.root.appendingPathComponent("whim.sqlite"),
                root: h.root.appendingPathComponent("Peer"), device: .iphone,
                credentials: credentials, transport: transport)
        }
        let first = try merge()
        let id = NoteID()
        try await h.store.delete(noteID: id)
        try await first.queueDeletion(id)
        try await first.flush()
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertTrue(transport.contexts.isEmpty)

        // Deferred work survives process exit and resumes when installation is observed.
        let restarted = try merge()
        transport.available = true
        try await restarted.activated()
        XCTAssertTrue(transport.sent.contains { $0.payload == .deletion(id) })
        XCTAssertEqual(transport.contexts.count, 1)
    }

    func testDestructiveRequestReplaysUntilAppliedAcknowledgementSurvivesCapture() async throws {
        for isReset in [false, true] {
            let source = try SyncHarness(); defer { source.remove() }
            let destination = try SyncHarness(); defer { destination.remove() }
            let outgoing = SyncTransport(); outgoing.active = true
            let incoming = SyncTransport(); incoming.active = true
            func sender() throws -> ConnectivityMergeService {
                try .init(store: source.store, files: source.files, databaseURL: source.root.appendingPathComponent("whim.sqlite"),
                    root: source.root.appendingPathComponent("Peer"), device: .iphone, transport: outgoing)
            }
            let receiver = try ConnectivityMergeService(store: destination.store, files: destination.files,
                databaseURL: destination.root.appendingPathComponent("whim.sqlite"), root: destination.root.appendingPathComponent("Peer"),
                device: .appleWatch, transport: incoming)
            let first = try sender()
            let id = NoteID()
            if isReset { let reset = try await first.prepareReset(); _ = try await first.apply(reset) }
            else { try await source.store.delete(noteID: id); try await first.queueDeletion(id) }
            try await first.flush()
            let payload: ConnectivityEnvelope.Payload = isReset ? .reset : .deletion(id)
            let request = try XCTUnwrap(outgoing.sent.first { $0.payload == payload })
            _ = try await receiver.apply(request); try await receiver.flush()
            let durable = try XCTUnwrap(incoming.sent.first { $0.payload == .acknowledgement(.durable(request.messageID)) })
            _ = try await first.apply(durable) // applied acknowledgement capture fails; only durable arrives
            let restarted = try sender()
            try await restarted.recover(); try await restarted.activated()
            XCTAssertEqual(outgoing.sent.filter { $0.messageID == request.messageID }.count, 2,
                "Destructive request stays replayable after durable-only acceptance")
            _ = try await receiver.apply(request); try await receiver.flush()
            let appliedPayload: ConnectivityEnvelope.Payload = isReset ? .acknowledgement(.reset(.appleWatch)) : .acknowledgement(.deletion(id, .appleWatch))
            let applied = try XCTUnwrap(incoming.sent.last { $0.payload == appliedPayload })
            _ = try await restarted.apply(applied)
            try await restarted.activated()
            XCTAssertEqual(outgoing.sent.filter { $0.messageID == request.messageID }.count, 2)
            if isReset {
                let status = try await restarted.status(); XCTAssertEqual(status.resetState, "synchronized")
            } else {
                let tombstone = try await source.store.deletions().first
                XCTAssertEqual(Set(tombstone?.acknowledgedEndpoints ?? []), [.iphone, .appleWatch])
            }
        }
    }

    func testTombstoneRecoversDeletionAfterOutboxWriteFails() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let transport = SyncTransport(); transport.active = true
        func merge() throws -> ConnectivityMergeService {
            try .init(store: h.store, files: h.files, databaseURL: h.root.appendingPathComponent("whim.sqlite"),
                root: h.root.appendingPathComponent("Peer"), device: .iphone, transport: transport)
        }
        let first = try merge()
        let id = NoteID()
        try await h.store.delete(noteID: id) // durable Delete before filesystem/outbox completion
        let injector = try DatabaseQueue(path: h.root.appendingPathComponent("whim.sqlite").path)
        try await injector.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_peer_outbox BEFORE INSERT ON peer_outbox BEGIN SELECT RAISE(FAIL, 'disk write failure'); END")
        }
        do { try await first.queueDeletion(id); XCTFail("Expected outgoing intent persistence to fail") } catch {}
        try await injector.write { db in try db.execute(sql: "DROP TRIGGER fail_peer_outbox") }
        let restarted = try merge()
        try await restarted.recover()
        try await restarted.activated()
        XCTAssertTrue(transport.sent.contains { $0.payload == .deletion(id) }, "Durable tombstone reconstructs interrupted outgoing deletion")
    }

    func testResetRequestAndGenerationRollBackTogetherWhenOutboxWriteFails() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let merge = try h.merge()
        let injector = try DatabaseQueue(path: h.root.appendingPathComponent("whim.sqlite").path)
        try await injector.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_peer_outbox BEFORE INSERT ON peer_outbox BEGIN SELECT RAISE(FAIL, 'disk write failure'); END")
        }
        do { _ = try await merge.prepareReset(); XCTFail("Expected reset request persistence to fail") } catch {}
        let generation = try await h.merge().generation()
        XCTAssertEqual(generation, .initial, "An unsent reset cannot advance a committed barrier")
        try await injector.write { db in try db.execute(sql: "DROP TRIGGER fail_peer_outbox") }
        let reset = try await merge.prepareReset()
        let transport = SyncTransport(); transport.active = true
        let restarted = try ConnectivityMergeService(store: h.store, files: h.files, databaseURL: h.root.appendingPathComponent("whim.sqlite"),
            root: h.root.appendingPathComponent("Peer"), device: .iphone, transport: transport)
        try await restarted.recover(); try await restarted.activated()
        XCTAssertTrue(transport.sent.contains { $0.messageID == reset.messageID && $0.payload == .reset })
    }

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
            XCTAssertTrue(premature.allSatisfy { !$0.hasLocalAudio }, "Metadata alone never claims playable local audio")
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

    func testInterruptedPendingCopyNeitherBlocksRecoveryNorSurvivesResend() async throws {
        for resendBeforeMetadata in [false, true] {
            let h = try SyncHarness(); defer { h.remove() }
            let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Watch recording",
                titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
                captureOutcome: .completed, requiresReview: false)
            let envelope = ConnectivityEnvelope(payload: .noteMetadata(metadata))
            _ = try await h.merge().receiveFile(at: h.fixture, metadata: envelope)
            try h.truncate(try h.pendingAudio(metadata.id))
            let restarted = try h.merge()
            if resendBeforeMetadata {
                _ = try await restarted.receiveFile(at: h.fixture, metadata: envelope)
                _ = try await restarted.apply(envelope)
            } else {
                _ = try await restarted.apply(envelope)
                try await restarted.recover()
                let notes = try await h.store.listNotes(filter: .all)
                XCTAssertEqual(notes.count, 1, "A truncated transfer remains visible without blocking recovery")
                XCTAssertFalse(try XCTUnwrap(notes.first).hasLocalAudio)
                _ = try await restarted.receiveFile(at: h.fixture, metadata: envelope)
            }
            let note = try await h.store.note(id: metadata.id)
            XCTAssertNil(h.files.audioError(at: try XCTUnwrap(note).audioURL))
            try await h.merge().recover()
        }
    }

    func testTruncatedNoteAudioFromInterruptedImportIsReplaced() async throws {
        let h = try SyncHarness(); defer { h.remove() }
        let metadata = NoteTransfer(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Watch recording",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)
        let envelope = ConnectivityEnvelope(payload: .noteMetadata(metadata))
        _ = try await h.merge().receiveFile(at: h.fixture, metadata: envelope)
        let audio = h.files.audioURL(for: metadata.id)
        try FileManager.default.createDirectory(at: audio.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: h.fixture, to: audio)
        try h.truncate(audio)
        let restarted = try h.merge()
        _ = try await restarted.apply(envelope)
        let note = try await h.store.note(id: metadata.id)
        XCTAssertNil(h.files.audioError(at: try XCTUnwrap(note).audioURL))
        try await restarted.recover()
    }
}

/// Scheduling fault injection only: every value and mutation comes from the real
/// SQLite store. Pause one already-read snapshot to model suspension of a process.
private actor PausingSynchronizationStore: WhimStore {
    let base: SQLiteWhimStore
    let paused: XCTestExpectation
    var reads = 0
    var released = false
    var continuation: CheckedContinuation<Void, Never>?
    init(base: SQLiteWhimStore, paused: XCTestExpectation) { self.base = base; self.paused = paused }
    func note(id: NoteID) async throws -> Note? {
        let snapshot = try await base.note(id: id)
        reads += 1
        if reads == 2 && !released {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                paused.fulfill()
            }
        }
        return snapshot
    }
    func resume() { released = true; continuation?.resume(); continuation = nil }
    func markAudioExpired(noteID: NoteID, at date: Date) async throws -> Bool { try await base.markAudioExpired(noteID: noteID, at: date) }
    func latestConfigurationRevision() async throws -> ConfigurationRevision? { try await base.latestConfigurationRevision() }
    func deliveryAttempts(noteID: NoteID) async throws -> [Attempt] { try await base.deliveryAttempts(noteID: noteID) }
    func beginRetryCycle(noteID: NoteID) async throws -> Bool { try await base.beginRetryCycle(noteID: noteID) }
    func markExhaustionNotified(noteID: NoteID, retryCycle: Int) async throws -> Bool { try await base.markExhaustionNotified(noteID: noteID, retryCycle: retryCycle) }
    func reset() async throws { try await base.reset() }
    func recordLocalError(_ error: LocalAudioError, noteID: NoteID) async throws { try await base.recordLocalError(error, noteID: noteID) }
    func saveRecoveryError(_ recording: FinalizedRecording, error: LocalAudioError) async throws { try await base.saveRecoveryError(recording, error: error) }
    func send(noteID: NoteID) async throws { try await base.send(noteID: noteID) }
    func saveRecordingSession(_ session: RecordingSession) async throws { try await base.saveRecordingSession(session) }
    func recordingSessions() async throws -> [RecordingSession] { try await base.recordingSessions() }
    func discardRecordingSession(sessionID: RecordingSessionID) async throws { try await base.discardRecordingSession(sessionID: sessionID) }
    func recordSessionError(_ error: LocalAudioError, sessionID: RecordingSessionID) async throws { try await base.recordSessionError(error, sessionID: sessionID) }
    func delete(noteID: NoteID) async throws { try await base.delete(noteID: noteID) }
    func acknowledgeDeletion(noteID: NoteID, endpoint: AttemptDevice) async throws { try await base.acknowledgeDeletion(noteID: noteID, endpoint: endpoint) }
    func deletions() async throws -> [DeletionTombstone] { try await base.deletions() }
    func saveConfigurationRevision(_ revision: ConfigurationRevision) async throws { try await base.saveConfigurationRevision(revision) }
    func configurationRevision(for noteID: NoteID) async throws -> ConfigurationRevision? { try await base.configurationRevision(for: noteID) }
    func listNotes(filter: NoteFilter) async throws -> [NoteProjection] { try await base.listNotes(filter: filter) }
    func saveFinalized(_ recording: FinalizedRecording) async throws -> Note { try await base.saveFinalized(recording) }
    func savePendingPeerNote(_ recording: FinalizedRecording) async throws -> Note { try await base.savePendingPeerNote(recording) }
    func setAudioSynchronization(_ value: AudioSynchronization?, noteID: NoteID) async throws { try await base.setAudioSynchronization(value, noteID: noteID) }
    func replaceAudioSynchronization(_ expected: AudioSynchronization, with value: AudioSynchronization, noteID: NoteID) async throws -> Bool {
        try await base.replaceAudioSynchronization(expected, with: value, noteID: noteID)
    }
    func updateTitle(noteID: NoteID, title: String, source: TitleSource) async throws { try await base.updateTitle(noteID: noteID, title: title, source: source) }
    func apply(_ event: DeliveryEvent, to noteID: NoteID) async throws -> Delivery { try await base.apply(event, to: noteID) }
    func acquireLease(_ kind: LeaseKind, noteID: NoteID, owner: UUID, until: Date) async throws -> Bool { try await base.acquireLease(kind, noteID: noteID, owner: owner, until: until) }
    func releaseLease(_ kind: LeaseKind, noteID: NoteID, owner: UUID) async throws { try await base.releaseLease(kind, noteID: noteID, owner: owner) }
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
    func merge(transport: (any PeerTransport)? = nil, device: AttemptDevice = .iphone) throws -> ConnectivityMergeService {
        try .init(store: store, files: files, databaseURL: root.appendingPathComponent("whim.sqlite"), root: root.appendingPathComponent("Peer"), device: device, transport: transport)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func pendingAudio(_ id: NoteID) throws -> URL {
        let peer = root.appendingPathComponent("Peer")
        let generations = try FileManager.default.contentsOfDirectory(at: peer, includingPropertiesForKeys: nil)
        return try XCTUnwrap(generations.map { $0.appendingPathComponent(id.rawValue.uuidString + ".m4a") }
            .first { FileManager.default.fileExists(atPath: $0.path) })
    }
    /// Leaves what an interrupted copy leaves: the start of the file under the final name.
    func truncate(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        try data.prefix(data.count / 3).write(to: url)
    }
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
    var available = true
    var contexts: [ConnectivityEnvelope] = []
    var sent: [ConnectivityEnvelope] = []
    var files: [URL] = []
    var fileEnvelopes: [ConnectivityEnvelope] = []
    var audioRequests: [AudioTransferRequest] {
        sent.compactMap { if case .audioRequest(let value) = $0.payload { value } else { nil } }
    }
    var isAvailable: Bool { available }
    var isActivated: Bool { active }
    func activate(receive: @escaping @Sendable (PeerEvent) -> Void) {}
    func transfer(_ envelope: ConnectivityEnvelope) throws { sent.append(envelope) }
    func transferFile(at url: URL, metadata: ConnectivityEnvelope) throws { files.append(url); fileEnvelopes.append(metadata) }
    func updateContext(_ envelope: ConnectivityEnvelope, credentials: StoredWebhookCredentials?) throws {
        guard available else { throw NSError(domain: "WCErrorDomain", code: 7006) }
        contexts.append(envelope)
    }
}
