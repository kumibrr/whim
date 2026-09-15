import Foundation
import GRDB
import XCTest
@testable import WhimCore

final class WhimServiceIntegrationTests: XCTestCase {
    func testSlowManualRetryDoesNotBlockStoppingAnActiveRecording() async throws {
        let harness = try WhimFacadeHarness(responses: [.init(statusCode: 400), .init(statusCode: 204)])
        defer { harness.remove() }
        _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"))
        let client = harness.makeService()
        _ = try await client.startRecording(source: .appleWatch)
        let finalized = try await client.stopRecording()
        let old = try XCTUnwrap(finalized)
        _ = try await waitForNote(client: client, status: .failed)
        _ = try await client.startRecording(source: .appleWatch)
        await harness.transport.suspendResponses()
        let retry = Task { try await client.retry(noteID: old.id) }
        await harness.transport.waitForRequestCount(2)
        let stopped = expectation(description: "Stop completes while retry HTTP remains suspended")
        let stop = Task {
            let note = try await client.stopRecording()
            stopped.fulfill()
            return note
        }
        await fulfillment(of: [stopped], timeout: 1)
        await harness.transport.resumeResponses()
        _ = try await retry.value
        let saved = try await stop.value
        XCTAssertNotNil(saved)
    }

    func testDeleteAndResetCancelAndJoinPendingManualRetry() async throws {
        for reset in [false, true] {
            let harness = try WhimFacadeHarness(responses: [.init(statusCode: 400), .init(statusCode: 204)])
            defer { harness.remove() }
            _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"))
            let client = harness.makeService()
            _ = try await client.startRecording(source: .appleWatch)
            let finalized = try await client.stopRecording()
            let old = try XCTUnwrap(finalized)
            _ = try await waitForNote(client: client, status: .failed)
            await harness.transport.suspendResponses()
            let retry = Task { try await client.retry(noteID: old.id) }
            await harness.transport.waitForRequestCount(2)
            let deleted = expectation(description: "Deletion cancels the suspended retry")
            let deletion = Task {
                if reset { try await client.reset() } else { try await client.delete(noteID: old.id) }
                deleted.fulfill()
            }
            await fulfillment(of: [deleted], timeout: 1)
            await harness.transport.resumeResponses()
            _ = try? await retry.value
            try await deletion.value
            let remaining = try await client.listNotes(filter: .all)
            XCTAssertTrue(remaining.isEmpty)
            let cancellations = await harness.transport.cancellationCount
            XCTAssertEqual(cancellations, 1)
        }
    }

    func testReconnectDuringTranscriptionResumesQueuedDeliveryAfterWorkflowCompletes() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let connected = FacadeConnectivity()
        let transcriber = BlockingFacadeTranscriber()
        _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"))
        let client = harness.makeService(transcriber: transcriber, isConnected: { await connected.read() })
        let events = FacadeEventProbe(stream: client.events())
        _ = try await client.startRecording(source: .iphone)
        let stopped = try await client.stopRecording()
        let note = try XCTUnwrap(stopped)
        await transcriber.waitUntilStarted()
        await connected.waitUntilRead()
        await connected.connect()
        try await client.resumeDelivery()
        try await client.resumeDelivery()
        transcriber.finish(with: "Recovered connectivity")

        let delivered = expectation(description: "pending reconnect reaches destination")
        Task { await events.waitForStatus(.sent, count: 1); delivered.fulfill() }
        await fulfillment(of: [delivered], timeout: 2)
        let requests = await harness.transport.requestCount
        XCTAssertEqual(requests, 1)
        let detail = try await client.note(id: note.id)
        XCTAssertEqual(detail?.status, .sent)
    }
    func testDetailDoesNotOfferPlaybackAfterLocalAudioDisappears() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService()
        _ = try await client.startRecording(source: .iphone)
        let finalized = try await client.stopRecording()
        let note = try XCTUnwrap(finalized)
        try harness.files.delete(noteID: note.id)
        let detail = try await client.note(id: note.id)
        XCTAssertFalse(try XCTUnwrap(detail).hasLocalAudio)
    }
    func testOfflineQueuedNoteResumesOnceOnConnectivityWake() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let connected = FacadeConnectivity()
        _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"))
        let client = harness.makeService(isConnected: { await connected.value })
        _ = try await client.startRecording(source: .iphone)
        let stopped = try await client.stopRecording()
        let note = try XCTUnwrap(stopped)
        try await Task.sleep(for: .milliseconds(30))
        let offline = try await client.note(id: note.id)
        XCTAssertEqual(offline?.status, .queued)
        XCTAssertEqual(offline?.attempts.count, 0)
        await connected.connect()
        try await client.resumeDelivery()
        try await client.resumeDelivery()
        await harness.transport.waitForRequestCount(1)
        try await Task.sleep(for: .milliseconds(30))
        let delivered = try await client.note(id: note.id)
        XCTAssertEqual(delivered?.status, .sent)
        let requests = await harness.transport.requestCount
        XCTAssertEqual(requests, 1)
    }
    func testPlaybackStopsBeforeCaptureAndCannotRestartDuringCapture() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService(playback: FacadePlayback())
        _ = try await client.startRecording(source: .iphone)
        let note = try await client.stopRecording()
        let id = try XCTUnwrap(note).id
        _ = try await client.playNote(id)
        let playing = await client.playbackSnapshot()
        XCTAssertEqual(playing?.noteID, id.rawValue.uuidString.lowercased())
        _ = try await client.startRecording(source: .iphone)
        let stopped = await client.playbackSnapshot()
        XCTAssertNil(stopped)
        do { _ = try await client.playNote(id); XCTFail("Cannot play while capturing") }
        catch { XCTAssertEqual(error as? WhimServiceError, .recordingActive) }
        try await client.discardRecording()
        _ = try await client.playNote(id)
        try await client.delete(noteID: id)
        let deleted = await client.playbackSnapshot()
        XCTAssertNil(deleted)
    }
    func testDeniedMicrophoneIsNotRequestedAgainOrAllowedToCapture() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let permissions = DeniedFacadePermissions()
        let client = harness.makeService(permissions: permissions)
        let status = try await client.requestPermission(.microphone)
        XCTAssertEqual(status, .denied)
        do { _ = try await client.startRecording(source: .iphone); XCTFail("Denied capture must fail") }
        catch { XCTAssertEqual(error as? WhimServiceError, .permissionDenied) }
        let requests = await permissions.requests
        XCTAssertEqual(requests, 0)
    }
    func testOnboardingCompletionPersistsAndResetClearsLocalLifecycle() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService()
        try await client.completeOnboarding()
        let completed = try await client.settings()
        XCTAssertTrue(completed.onboardingCompleted)
        try await client.reset()
        let reset = try await client.settings()
        XCTAssertFalse(reset.onboardingCompleted)
    }
    func testSettingsReadAndPatchPreserveMaskedSecretsAndEndpointQuery() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService()
        _ = try await client.updateWebhook(.init(endpoint: "https://example.com/whim?key=private",
            bearerToken: "bearer-private", hmacSecret: "hmac-private",
            customHeaders: [.init(name: "X-Secret", value: "header-private", isSecret: true)]))
        _ = try await client.patchWebhook(.init(bearerToken: .init(action: .preserve)))
        let settings = try await client.settings()
        let encoded = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        XCTAssertTrue(settings.webhook?.hasBearerToken == true)
        XCTAssertTrue(settings.webhook?.hasHMACSecret == true)
        XCTAssertEqual(settings.webhook?.destination.path, "/whim")
        XCTAssertFalse(encoded.contains("private"))
        let revision = try await harness.store.latestConfigurationRevision()
        let credentials = try await harness.credentials.credentials(for: XCTUnwrap(revision).id)
        XCTAssertEqual(credentials?.endpoint.absoluteString, "https://example.com/whim?key=private")
        XCTAssertEqual(credentials?.bearerToken, "bearer-private")
        XCTAssertEqual(settings.watch.availability, "unavailable")
    }
    func testEventSubscriptionCancellationDoesNotTerminateFutureSubscriptions() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client: any WhimClient = harness.makeService()
        let firstStream = client.events()
        let first = Task { for await _ in firstStream { } }
        first.cancel()
        await first.value
        let secondStream = client.events()
        let received = Task { () -> WhimEvent? in
            for await event in secondStream { return event }
            return nil
        }

        _ = try await client.startRecording(source: .iphone)
        let event = await received.value

        XCTAssertEqual(event?.type, .recordingStarted)
    }

    func testUserDefaultsPreferencesPersistAcrossInstancesAndResetTruthfully() async throws {
        let suite = "app.whim.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let input = PreferenceInput(retentionPolicy: .ninetyDays, transcriptionEnabled: false,
            transcriptionLocaleIdentifier: "es-ES")
        try UserDefaultsPreferenceStore(suiteName: suite).save(input)

        let reopened = try UserDefaultsPreferenceStore(suiteName: suite).load()
        try UserDefaultsPreferenceStore(suiteName: suite).reset()
        let reset = try UserDefaultsPreferenceStore(suiteName: suite).load()

        XCTAssertEqual(reopened, input)
        XCTAssertEqual(reset, .default)
    }
    func testRecoveredNoteWaitsForExplicitSendThroughPublicClient() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let session = RecordingSession(id: RecordingSessionID(), noteID: NoteID(),
            createdAt: Date(timeIntervalSince1970: 1_000), source: .iphone)
        try await harness.store.saveRecordingSession(session)
        try writeAudioFixture(to: harness.files.temporaryURL(for: session.id))
        _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"),
            now: Date(timeIntervalSince1970: 1_000))
        let client: any WhimClient = harness.makeService()

        let recovered = try await client.listNotes(filter: .all)
        let requestsBeforeReview = await harness.transport.requestCount
        try await client.sendRecovered(noteID: session.noteID)
        let requestsAfterSend = await harness.transport.requestCount
        let sent = try await client.note(id: session.noteID)

        XCTAssertEqual(recovered.first?.requiresReview, true)
        XCTAssertEqual(requestsBeforeReview, 0)
        XCTAssertEqual(requestsAfterSend, 1)
        XCTAssertEqual(sent?.status, .sent)
    }

    func testSentAttemptDetailSurvivesReceiptReductionAndStoreReopen() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let session = RecordingSession(id: RecordingSessionID(), noteID: NoteID(),
            createdAt: Date(timeIntervalSince1970: 1_000), source: .iphone)
        try await harness.store.saveRecordingSession(session)
        try writeAudioFixture(to: harness.files.temporaryURL(for: session.id))
        _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"),
            now: Date(timeIntervalSince1970: 1_000))
        let persistedRevision = try await harness.store.latestConfigurationRevision()
        let revision = try XCTUnwrap(persistedRevision)
        let client: any WhimClient = harness.makeService()
        _ = try await client.listNotes(filter: .all)

        try await client.sendRecovered(noteID: session.noteID)
        let persistedAttempts = try await harness.store.deliveryAttempts(noteID: session.noteID)
        let live = try await client.note(id: session.noteID)
        let reopenedStore = try SQLiteWhimStore.open(at: harness.databaseURL, now: { harness.clock.now })
        let reopenedClient: any WhimClient = harness.makeService(store: reopenedStore)
        let reopened = try await reopenedClient.note(id: session.noteID)

        XCTAssertEqual(persistedAttempts.count, 1)
        for detail in [live, reopened] {
            XCTAssertEqual(detail?.attempts.count, 1)
            XCTAssertEqual(detail?.attempts.first?.outcome, .sent)
            XCTAssertEqual(detail?.attempts.first?.configurationRevisionID,
                revision.id.rawValue.uuidString.lowercased())
            XCTAssertEqual(detail?.attempts.first?.destination.host, "example.com")
            XCTAssertEqual(detail?.attempts.first?.responseStatusCode, 204)
        }
    }

    func testStopReturnsPromptlyWhileDeliveryAndOneSharedTitleJobContinue() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"))
        let transcriber = BlockingFacadeTranscriber()
        await harness.transport.suspendResponses()
        let client: any WhimClient = harness.makeService(transcriber: transcriber)
        let events = FacadeEventProbe(stream: client.events())
        _ = try await client.startRecording(source: .iphone)

        let stopping = Task { try await client.stopRecording() }
        await transcriber.waitUntilStarted()
        await harness.transport.waitForRequestCount(1)
        let completed = expectation(description: "stop returns after finalization")
        Task { _ = try? await stopping.value; completed.fulfill() }
        await fulfillment(of: [completed], timeout: 0.2)
        let transcriptionCount = transcriber.callCount
        let transportCount = await harness.transport.requestCount
        await events.waitForStatus(.sending, count: 1)
        await harness.transport.resumeResponses()
        let stopped = try await stopping.value
        transcriber.finish(with: "A later local title")

        XCTAssertEqual(transcriptionCount, 1)
        XCTAssertEqual(transportCount, 1)
        XCTAssertEqual(stopped?.status, .queued)
    }

    func testScheduledAttemptPublishesSendingBeforeTransportCompletes() async throws {
        let harness = try WhimFacadeHarness(responses: [
            HTTPResponse(statusCode: 500), HTTPResponse(statusCode: 204),
        ])
        defer { harness.remove() }
        _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"))
        let client: any WhimClient = harness.makeService()
        let events = FacadeEventProbe(stream: client.events())
        _ = try await client.startRecording(source: .iphone)
        _ = try await client.stopRecording()
        await harness.scheduler.waitForCount(1)
        await events.waitForStatus(.sending, count: 1)

        harness.clock.advance(by: 61)
        await harness.transport.suspendResponses()
        let scheduled = Task { try await harness.scheduler.runNext() }
        await harness.transport.waitForRequestCount(2)
        await events.waitForStatus(.sending, count: 2)
        let whileBlocked = try await client.listNotes(filter: .all).first
        await harness.transport.resumeResponses()
        try await scheduled.value

        XCTAssertEqual(whileBlocked?.status, .sending)
    }

    func testAutomaticDeliveryPreparationFailureBecomesSanitizedFailedProjection() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"))
        let builder = WebhookRequestBuilder(makeBodyFileURL: { _ in throw POSIXError(.ENOSPC) })
        let client: any WhimClient = harness.makeService(requestBuilder: builder)
        let events = FacadeEventProbe(stream: client.events())
        _ = try await client.startRecording(source: .iphone)
        let stopped = try await client.stopRecording()

        await events.waitForWorkflowError(.deliveryPreparationFailed)
        let failed = try await client.note(id: try XCTUnwrap(stopped?.id))

        XCTAssertEqual(failed?.status, .failed)
        XCTAssertEqual(failed?.workflowError, .deliveryPreparationFailed)
        XCTAssertTrue(failed?.attempts.isEmpty == true)
        let requestCount = await harness.transport.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    // Break: a known HTTP outcome whose local write fails remains Sending and Retry cannot recover it.
    func testKnownHTTPOutcomeWriteFailureIsActionableWithoutDuplicateTransport() async throws {
        for statusCode in [204, 400] {
            let harness = try WhimFacadeHarness(responses: [HTTPResponse(statusCode: statusCode)])
            defer { harness.remove() }
            _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"))
            let injector = try DatabaseQueue(path: harness.databaseURL.path)
            let trigger = statusCode == 204 ? "fail_receipt_outcome" : "fail_failure_outcome"
            let target = statusCode == 204
                ? "BEFORE INSERT ON receipts"
                : "BEFORE UPDATE OF failure ON attempts WHEN NEW.failure IS NOT NULL"
            try await injector.write { db in
                try db.execute(sql: """
                    CREATE TRIGGER \(trigger) \(target)
                    BEGIN SELECT RAISE(ABORT, 'injected known outcome write failure'); END
                    """)
            }
            let client: any WhimClient = harness.makeService()
            let events = FacadeEventProbe(stream: client.events())
            _ = try await client.startRecording(source: .iphone)
            let stopped = try await client.stopRecording()
            let noteID = try XCTUnwrap(stopped?.id)

            await events.waitForWorkflowError(.deliveryPersistenceFailed)
            let actionable = try await client.note(id: noteID)
            XCTAssertEqual(actionable?.status, .failed, "HTTP \(statusCode)")
            XCTAssertEqual(actionable?.workflowError, .deliveryPersistenceFailed, "HTTP \(statusCode)")
            XCTAssertEqual(actionable?.attempts.map(\.outcome), [.sending], "HTTP \(statusCode)")
            let requestCountAfterFailure = await harness.transport.requestCount
            XCTAssertEqual(requestCountAfterFailure, 1, "HTTP \(statusCode)")

            try await injector.write { db in try db.execute(sql: "DROP TRIGGER \(trigger)") }
            try await client.retry(noteID: noteID)
            let recovered = try await client.note(id: noteID)

            XCTAssertNil(recovered?.workflowError, "HTTP \(statusCode)")
            XCTAssertEqual(recovered?.status, statusCode == 204 ? .sent : .failed, "HTTP \(statusCode)")
            XCTAssertEqual(recovered?.attempts.map(\.outcome), [statusCode == 204 ? .sent : .failed],
                "HTTP \(statusCode)")
            XCTAssertEqual(recovered?.attempts.first?.responseStatusCode, statusCode, "HTTP \(statusCode)")
            let requestCountAfterRecovery = await harness.transport.requestCount
            XCTAssertEqual(requestCountAfterRecovery, 1, "HTTP \(statusCode)")
        }
    }

    func testInterruptionFinalizationStartsWorkflowAndPublishesResult() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"))
        let client: any WhimClient = harness.makeService()
        let stream = client.events()
        _ = try await client.startRecording(source: .iphone)

        await harness.recorder.emit(.interruption)
        let sent = try await waitForNote(client: client, status: .sent)
        let events = await collectEvents(stream, until: .noteChanged)
        let requestCount = await harness.transport.requestCount

        XCTAssertEqual(sent?.status, .sent)
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(events.contains { $0.type == .recordingStopped })
        XCTAssertTrue(events.contains { $0.type == .noteChanged })
    }

    func testSameDeviceCommandsStaySerializedAcrossPreferenceAwait() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let preferences = BlockingFacadePreferences()
        let client: any WhimClient = harness.makeService(preferences: preferences)
        let update = Task { try await client.updatePreferences(.init(retentionPolicy: .sevenDays,
            transcriptionEnabled: false, transcriptionLocaleIdentifier: nil)) }
        await preferences.waitUntilSaving()

        let start = Task { try await client.startRecording(source: .iphone) }
        for _ in 0..<20 { await Task.yield() }
        let startsWhilePreferenceSuspended = await harness.recorder.startCount
        await preferences.finishSaving()
        try await update.value
        _ = try await start.value

        XCTAssertEqual(startsWhilePreferenceSuspended, 0)
    }

    func testResetActuallyRemovesLocalStateCredentialsAudioAndPreferences() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let session = RecordingSession(id: RecordingSessionID(), noteID: NoteID(), createdAt: Date(), source: .iphone)
        try await harness.store.saveRecordingSession(session)
        try writeAudioFixture(to: harness.files.temporaryURL(for: session.id))
        _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"))
        let client: any WhimClient = harness.makeService()
        _ = try await client.listNotes(filter: .all)
        try await client.updatePreferences(.init(retentionPolicy: .never, transcriptionEnabled: false,
            transcriptionLocaleIdentifier: "es-ES"))

        try await client.reset()

        let remaining = try await client.listNotes(filter: .all)
        let credentialCount = await harness.credentials.count
        let preferences = await harness.preferences.load()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(credentialCount, 0)
        XCTAssertEqual(preferences, .default)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.files.audioURL(for: session.noteID).path))
    }

    func testResetCancelsAndJoinsInFlightWorkflowBeforeDeleting() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"))
        await harness.transport.suspendResponses()
        let transcriber = BlockingFacadeTranscriber()
        let client: any WhimClient = harness.makeService(transcriber: transcriber)
        _ = try await client.startRecording(source: .iphone)
        let projection = try await client.stopRecording()
        await harness.transport.waitForRequestCount(1)

        try await client.reset()
        await harness.transport.resumeResponses()
        transcriber.finish(with: "Must not resurrect")

        let remaining = try await client.listNotes(filter: .all)
        let cancellationCount = await harness.transport.cancellationCount
        XCTAssertNotNil(projection)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertGreaterThanOrEqual(cancellationCount, 1)
    }

    func testEventsRemainMonotonicAndPublishStoppedNoteOnlyAfterBothStepsComplete() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"))
        let client: any WhimClient = harness.makeService()
        let stream = client.events()
        _ = try await client.startRecording(source: .iphone)
        _ = try await client.stopRecording()
        await harness.transport.waitForRequestCount(1)
        _ = try await waitForNote(client: client, status: .sent)
        var iterator = stream.makeAsyncIterator()
        var events: [WhimEvent] = []
        while events.last?.note?.status != .sent, let event = await iterator.next() { events.append(event) }

        XCTAssertEqual(events.map(\.sequence), Array(1...events.count).map(UInt64.init))
        XCTAssertEqual(events.prefix(3).map(\.type), [.recordingStarted, .recordingStopped, .noteChanged])
        XCTAssertEqual(events.last?.note?.status, .sent)
    }
}

private func waitForNote(client: any WhimClient, status: DeliveryStatus) async throws -> NoteDetailProjection? {
    for _ in 0..<100 {
        if let note = try await client.listNotes(filter: .all).first,
           note.status == status { return try await client.note(id: note.id) }
        try await Task.sleep(for: .milliseconds(5))
    }
    XCTFail("Note never reached \(status.rawValue)")
    return nil
}

private func collectEvents(_ stream: AsyncStream<WhimEvent>, until kind: WhimEvent.Kind) async -> [WhimEvent] {
    let result = Task { () -> [WhimEvent] in
        var values: [WhimEvent] = []
        for await event in stream {
            values.append(event)
            if event.type == kind { return values }
        }
        return values
    }
    let timeout = Task {
        try? await Task.sleep(for: .seconds(1))
        result.cancel()
    }
    let values = await result.value
    timeout.cancel()
    return values
}

private final class WhimFacadeHarness: @unchecked Sendable {
    let root: URL
    let store: SQLiteWhimStore
    let files: AudioFileStore
    let recorder = FacadeRecorder()
    let credentials = FacadeCredentials()
    let transport: FacadeTransport
    let scheduler = FacadeScheduler()
    let clock: FacadeClock
    let preferences = FacadePreferences()
    let configuration: WebhookConfigurationService

    var databaseURL: URL { root.appendingPathComponent("whim.sqlite") }

    init(responses: [HTTPResponse] = [HTTPResponse(statusCode: 204)]) throws {
        let clock = FacadeClock(Date(timeIntervalSince1970: 1_000))
        self.clock = clock
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = try SQLiteWhimStore.open(at: root.appendingPathComponent("whim.sqlite"), now: { clock.now })
        files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        transport = FacadeTransport(responses: responses)
        configuration = WebhookConfigurationService(store: store, credentials: credentials)
    }

    func makeService(transcriber: any Transcriber = EmptyFacadeTranscriber(),
                     isConnected: @escaping @Sendable () async -> Bool = { true },
                     playback: any PlaybackAdapter = SystemPlaybackAdapter(),
                     permissions: any PermissionAdapter = SystemPermissionAdapter(),
                     preferences: (any PreferenceStoring)? = nil,
                     store selectedStore: (any WhimStore)? = nil,
                     requestBuilder: WebhookRequestBuilder = WebhookRequestBuilder()) -> WhimService {
        let selectedStore = selectedStore ?? store
        let title = TitleService(transcriber: transcriber, store: selectedStore)
        let delivery = DeliveryService(store: selectedStore, credentials: credentials, transport: transport,
            notifications: FacadeNotifications(), clock: clock, scheduler: scheduler, isConnected: isConnected,
            requestBuilder: requestBuilder,
            titleSnapshot: { await title.enrich($0) }, scheduledFailure: { _, _ in },
            appVersion: "1.0.0", appBuild: "1")
        let recording = RecordingService(recorder: recorder, store: selectedStore, files: files)
        let configurationTest = ConfigurationTestService(credentials: credentials, transport: transport,
            fixtureAudioURL: root.appendingPathComponent("test.m4a"), appVersion: "1.0.0", appBuild: "1")
        return WhimService(recording: recording, store: selectedStore, files: files, title: title,
            delivery: delivery, configuration: configuration, configurationTest: configurationTest,
            recovery: RecoveryScanner(store: selectedStore, files: files), preferences: preferences ?? self.preferences,
            credentials: credentials, scheduler: scheduler, permissions: permissions, playback: playback)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private actor DeniedFacadePermissions: PermissionAdapter {
    private(set) var requests = 0
    func status(_ kind: PermissionKind) -> PermissionStatus { .denied }
    func request(_ kind: PermissionKind) -> PermissionStatus { requests += 1; return .denied }
    func openSettings() {}
}

private actor FacadeConnectivity {
    private(set) var value = false
    private var readOccurred = false
    private var readers: [CheckedContinuation<Void, Never>] = []
    func read() -> Bool {
        readOccurred = true
        readers.forEach { $0.resume() }; readers.removeAll()
        return value
    }
    func waitUntilRead() async {
        if readOccurred { return }
        await withCheckedContinuation { readers.append($0) }
    }
    func connect() { value = true }
}

private actor FacadePlayback: PlaybackAdapter {
    private var value: PlaybackProjection?
    func play(noteID: NoteID, url: URL) -> PlaybackProjection {
        let next = PlaybackProjection(noteID: noteID, isPlaying: true, elapsedSeconds: 0, durationSeconds: 2)
        value = next; return next
    }
    func stop() { value = nil }
    func snapshot() -> PlaybackProjection? { value }
}

private actor FacadeRecorder: AudioRecorder {
    private let pair = AsyncStream.makeStream(of: RecordingEvent.self)
    private(set) var startCount = 0
    func events() -> AsyncStream<RecordingEvent> { pair.stream }
    func start(at url: URL) throws { startCount += 1; try writeAudioFixture(to: url) }
    func stop() { pair.continuation.yield(.encoderCompleted(duration: 1, peakPowerDBFS: -10)) }
    func discard() {}
    func emit(_ event: RecordingEvent) { pair.continuation.yield(event) }
}

private struct EmptyFacadeTranscriber: Transcriber {
    func transcribe(audioAt url: URL, locale: Locale) async throws -> String { "" }
}

private final class BlockingFacadeTranscriber: Transcriber, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var terminal: Result<String, Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var calls = 0
    var callCount: Int { lock.withLock { calls } }
    func transcribe(audioAt url: URL, locale: Locale) async throws -> String {
        lock.withLock { calls += 1; waiters.forEach { $0.resume() }; waiters.removeAll() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let terminal = lock.withLock { () -> Result<String, Error>? in
                    if let terminal { return terminal }
                    self.continuation = continuation
                    return nil
                }
                if let terminal { continuation.resume(with: terminal) }
            }
        } onCancel: {
            self.resolve(.failure(CancellationError()))
        }
    }
    func waitUntilStarted() async {
        await withCheckedContinuation { waiter in
            let alreadyStarted = lock.withLock { () -> Bool in
                guard calls == 0 else { return true }
                waiters.append(waiter)
                return false
            }
            if alreadyStarted { waiter.resume() }
        }
    }
    func finish(with value: String) { resolve(.success(value)) }
    private func resolve(_ value: Result<String, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<String, Error>? in
            guard terminal == nil else { return nil }
            terminal = value
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(with: value)
    }
}

private actor FacadeCredentials: CredentialStore {
    private var values: [ConfigurationRevisionID: StoredWebhookCredentials] = [:]
    func save(_ credentials: StoredWebhookCredentials, for revisionID: ConfigurationRevisionID) { values[revisionID] = credentials }
    func credentials(for revisionID: ConfigurationRevisionID) -> StoredWebhookCredentials? { values[revisionID] }
    func remove(for revisionID: ConfigurationRevisionID) { values[revisionID] = nil }
    func removeAll() { values.removeAll() }
    var count: Int { values.count }
}

private actor FacadeTransport: HTTPTransport {
    private(set) var requestCount = 0
    private(set) var cancellationCount = 0
    private var responses: [HTTPResponse]
    private var suspended = false
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    init(responses: [HTTPResponse]) { self.responses = responses }
    func send(_ request: WebhookRequest) async throws -> HTTPResponse {
        requestCount += 1
        let ready = waiters.filter { requestCount >= $0.0 }
        waiters.removeAll { requestCount >= $0.0 }
        ready.forEach { $0.1.resume() }
        while suspended {
            do { try await Task.sleep(for: .milliseconds(5)) }
            catch { cancellationCount += 1; throw error }
        }
        return responses.isEmpty ? HTTPResponse(statusCode: 204) : responses.removeFirst()
    }
    func waitForRequestCount(_ count: Int) async {
        if requestCount >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func suspendResponses() { suspended = true }
    func resumeResponses() { suspended = false }
}

private actor FacadeScheduler: DeliveryScheduler {
    private typealias Operation = @Sendable () async throws -> Void
    private var operations: [Operation] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func schedule(noteID: NoteID, earliest: Date,
        operation: @escaping @Sendable () async throws -> Void,
        onFailure: @escaping @Sendable (any Error) async -> Void) {
        operations.append(operation)
        let ready = waiters.filter { operations.count >= $0.0 }
        waiters.removeAll { operations.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
    func cancel(noteID: NoteID) { operations.removeAll() }
    func waitForCount(_ count: Int) async {
        if operations.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func runNext() async throws { try await operations.removeFirst()() }
}

private final class FacadeClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.withLock { value } }
    func advance(by interval: TimeInterval) { lock.withLock { value.addTimeInterval(interval) } }
}

private final class FacadeEventProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [DeliveryStatus] = []
    private var workflowErrors: [DeliveryWorkflowError] = []
    private var statusWaiters: [(DeliveryStatus, Int, CheckedContinuation<Void, Never>)] = []
    private var errorWaiters: [(DeliveryWorkflowError, CheckedContinuation<Void, Never>)] = []
    private var task: Task<Void, Never>?

    init(stream: AsyncStream<WhimEvent>) {
        task = Task { [weak self] in
            for await event in stream {
                guard let note = event.note else { continue }
                self?.record(status: note.status, workflowError: note.workflowError)
            }
        }
    }

    deinit { task?.cancel() }

    func waitForStatus(_ status: DeliveryStatus, count: Int) async {
        await withCheckedContinuation { continuation in
            let alreadyObserved = lock.withLock { () -> Bool in
                guard statuses.count(where: { $0 == status }) < count else { return true }
                statusWaiters.append((status, count, continuation))
                return false
            }
            if alreadyObserved { continuation.resume() }
        }
    }

    func waitForWorkflowError(_ error: DeliveryWorkflowError) async {
        await withCheckedContinuation { continuation in
            let alreadyObserved = lock.withLock { () -> Bool in
                guard !workflowErrors.contains(error) else { return true }
                errorWaiters.append((error, continuation))
                return false
            }
            if alreadyObserved { continuation.resume() }
        }
    }

    private func record(status: DeliveryStatus, workflowError: DeliveryWorkflowError?) {
        let ready = lock.withLock { () -> ([CheckedContinuation<Void, Never>], [CheckedContinuation<Void, Never>]) in
            statuses.append(status)
            if let workflowError { workflowErrors.append(workflowError) }
            let readyStatuses = statusWaiters.filter { waiter in
                statuses.count(where: { value in value == waiter.0 }) >= waiter.1
            }
            statusWaiters.removeAll { waiter in
                statuses.count(where: { $0 == waiter.0 }) >= waiter.1
            }
            let readyErrors = errorWaiters.filter { workflowErrors.contains($0.0) }
            errorWaiters.removeAll { workflowErrors.contains($0.0) }
            return (readyStatuses.map(\.2), readyErrors.map(\.1))
        }
        (ready.0 + ready.1).forEach { $0.resume() }
    }
}

private struct FacadeNotifications: DeliveryNotificationAdapter {
    func notifyFailure(title: String, reason: String, noteID: NoteID) async {}
}

private actor FacadePreferences: PreferenceStoring {
    private var value = PreferenceInput.default
    func load() -> PreferenceInput { value }
    func save(_ input: PreferenceInput) { value = input }
    func reset() { value = .default }
}

private actor BlockingFacadePreferences: PreferenceStoring {
    private var saveContinuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func load() -> PreferenceInput { .default }
    func save(_ input: PreferenceInput) async {
        waiters.forEach { $0.resume() }; waiters.removeAll()
        await withCheckedContinuation { saveContinuation = $0 }
    }
    func reset() {}
    func waitUntilSaving() async {
        if saveContinuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func finishSaving() { saveContinuation?.resume(); saveContinuation = nil }
}
