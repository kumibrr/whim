import Foundation
import XCTest
@testable import WhimCore

final class DeliveryServiceTests: XCTestCase {
    // Break: retry scheduling creates duplicate wakeups or never invokes its delivery callback.
    func testInProcessSchedulerKeepsOnePendingWakePerNoteAndInvokesCallback() async throws {
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000))
        let sleeper = ControlledDeliverySleeper()
        let callbacks = NoteIDRecorder()
        let scheduler = InProcessDeliveryScheduler(clock: clock, sleeper: sleeper)
        let noteID = NoteID()

        await scheduler.schedule(noteID: noteID, earliest: Date(timeIntervalSince1970: 1_060)) {
            await callbacks.append(noteID)
        }
        await scheduler.schedule(noteID: noteID, earliest: Date(timeIntervalSince1970: 1_120)) {
            XCTFail("A later duplicate wake replaced the existing retry")
        }

        await sleeper.waitUntilCalled()
        let requestedIntervals = await sleeper.requestedIntervals
        XCTAssertEqual(requestedIntervals, [60])
        await sleeper.resumeNext()
        await callbacks.waitForCount(1)
        let values = await callbacks.values
        XCTAssertEqual(values, [noteID])
    }

    // Break: being offline creates an Attempt or acquires delivery execution resources.
    func testOfflineQueuesWithoutAttempt() async throws {
        let h = try DeliveryHarness(connected: false)
        let result = try await h.service.deliver(noteID: h.note.id)
        let stored = await h.store.note(id: h.note.id)
        let requestCount = await h.fakeTransport.requestCount
        let leaseAcquireCount = await h.store.leaseAcquireCount
        XCTAssertEqual(result, .queued)
        XCTAssertTrue(stored!.delivery.activeAttempts.isEmpty)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(leaseAcquireCount, 0)
    }

    // Break: a 2xx does not persist a Receipt, releases the lease late, or a second call resends it.
    func testSuccessPersistsReceiptAndNeverResends() async throws {
        let h = try DeliveryHarness(responses: [.success(.init(statusCode: 204))])
        let first = try await h.service.deliver(noteID: h.note.id)
        let persisted = await h.store.note(id: h.note.id)
        let leaseHeld = await h.store.leaseHeld
        let second = try await h.service.deliver(noteID: h.note.id)
        let count = await h.fakeTransport.requestCount
        XCTAssertEqual(first, .sent)
        XCTAssertEqual(persisted?.delivery.receipt?.statusCode, 204)
        XCTAssertFalse(leaseHeld)
        XCTAssertEqual(second, .alreadySent)
        XCTAssertEqual(count, 1)
    }

    // Break: concurrent workers overlap transport or a thrown transport path retains the lease.
    func testLeaseExcludesOverlapAndReleasesOnTransportFailure() async throws {
        let gate = TransportGate()
        let h = try DeliveryHarness(transport: gate)
        async let first = h.service.deliver(noteID: h.note.id)
        await gate.waitUntilCalled()
        let overlap = try await h.service.deliver(noteID: h.note.id)
        XCTAssertEqual(overlap, .busy)
        await gate.fail()
        let completed = try await first
        let leaseHeld = await h.store.leaseHeld
        let leaseOwners = await h.store.leaseOwners
        XCTAssertEqual(completed, .scheduled(Date(timeIntervalSince1970: 1_060)))
        XCTAssertFalse(leaseHeld)
        XCTAssertEqual(Set(leaseOwners).count, 2)
    }

    // Break: a Receipt arriving after preflight but before lease acquisition is sent again.
    func testReceiptAfterPreflightBeforeLeasePreventsTransport() async throws {
        let h = try DeliveryHarness(responses: [.success(.init(statusCode: 204))])
        await h.store.setReceiptOnAcquire(true)
        let result = try await h.service.deliver(noteID: h.note.id)
        let requestCount = await h.fakeTransport.count()
        let leaseHeld = await h.store.isLeaseHeld()
        XCTAssertEqual(result, .alreadySent)
        XCTAssertEqual(requestCount, 0)
        XCTAssertFalse(leaseHeld)
    }

    // Break: retry eligibility is returned but never handed to the bounded scheduler.
    func testRetrySchedulesOnlyCurrentNoteEarliestEligibility() async throws {
        let scheduler = SchedulerFake()
        let h = try DeliveryHarness(responses: [.success(.init(statusCode: 500))], scheduler: scheduler)
        let result = try await h.service.deliver(noteID: h.note.id)
        XCTAssertEqual(result, .scheduled(Date(timeIntervalSince1970: 1_060)))
        let entries = await scheduler.entries
        XCTAssertEqual(entries, [.init(noteID: h.note.id, earliest: Date(timeIntervalSince1970: 1_060))])
    }

    // Break: an in-process retry wake resends a Note whose Receipt arrived while it was sleeping.
    func testScheduledCallbackRechecksReceiptBeforeTransport() async throws {
        let scheduler = SchedulerFake()
        let h = try DeliveryHarness(responses: [.success(.init(statusCode: 500))], scheduler: scheduler)
        _ = try await h.service.deliver(noteID: h.note.id)
        let attempt = await h.store.note(id: h.note.id)!.delivery.failedAttempts[0].attempt
        await h.store.seed(.receipt(.init(attemptID: attempt.id, noteID: h.note.id,
            receivedAt: Date(timeIntervalSince1970: 1_010), statusCode: 200)))

        await scheduler.run(noteID: h.note.id)

        let requestCount = await h.fakeTransport.count()
        XCTAssertEqual(requestCount, 1)
    }

    // Break: missing local audio consumes retry state as a network Attempt.
    func testMissingAudioBecomesLocalFailureWithoutAttempt() async throws {
        let h = try DeliveryHarness(responses: [], writeAudio: false)
        let result = try await h.service.deliver(noteID: h.note.id)
        let note = await h.store.note(id: h.note.id)!
        XCTAssertEqual(result, .failed)
        XCTAssertEqual(note.localError, .missing)
        XCTAssertTrue(note.delivery.failedAttempts.isEmpty)
        XCTAssertTrue(note.delivery.activeAttempts.isEmpty)
    }

    // Break: Watch delivery records an iPhone Attempt.
    func testAttemptUsesInjectedDeviceIdentity() async throws {
        let h = try DeliveryHarness(responses: [.success(.init(statusCode: 500))], device: .appleWatch)
        _ = try await h.service.deliver(noteID: h.note.id)
        let attempt = await h.store.note(id: h.note.id)!.delivery.failedAttempts.first?.attempt
        XCTAssertEqual(attempt?.device, .appleWatch)
    }

    // Break: retry classes, Retry-After, error cap/redaction, or exhaustion notification drift.
    func testRetrySchedulingExhaustionAndSanitizedExcerpt() async throws {
        let secretBody = "TITLE TOKEN QUERY HEADER " + String(repeating: "x", count: 5_000)
        let h = try DeliveryHarness(responses: [
            .success(.init(statusCode: 429, headers: ["Retry-After": "120"], body: Data(secretBody.utf8))),
            .success(.init(statusCode: 500)),
            .success(.init(statusCode: 408)),
        ])
        let first = try await h.service.deliver(noteID: h.note.id)
        XCTAssertEqual(first, .scheduled(Date(timeIntervalSince1970: 1_120)))
        h.clock.set(Date(timeIntervalSince1970: 1_120))
        _ = try await h.service.deliver(noteID: h.note.id)
        h.clock.set(Date(timeIntervalSince1970: 2_020))
        let third = try await h.service.deliver(noteID: h.note.id)
        let persisted = await h.store.note(id: h.note.id)!
        XCTAssertEqual(third, .failed)
        XCTAssertEqual(persisted.delivery.failedAttempts.count, 3)
        XCTAssertLessThanOrEqual(persisted.delivery.failedAttempts[0].responseExcerpt?.utf8.count ?? 0,
            DeliveryTimeouts.maximumErrorExcerptBytes)
        for value in ["TITLE", "TOKEN", "QUERY", "HEADER"] {
            XCTAssertFalse(persisted.delivery.failedAttempts[0].responseExcerpt?.contains(value) == true)
        }
        let notificationsAfterFailure = await h.notifications.count
        let exhausted = try await h.service.deliver(noteID: h.note.id)
        let notificationsAfterReplay = await h.notifications.count
        XCTAssertEqual(notificationsAfterFailure, 1)
        XCTAssertEqual(exhausted, .failed)
        XCTAssertEqual(notificationsAfterReplay, 1)
    }

    // Break: manual Retry erases history or remains exhausted instead of allowing a fresh three failures.
    func testManualRetryPersistsFreshCycleWhilePreservingHistory() async throws {
        let h = try DeliveryHarness(responses: Array(repeating: .success(.init(statusCode: 500)), count: 4))
        _ = try await h.service.deliver(noteID: h.note.id)
        h.clock.set(Date(timeIntervalSince1970: 1_060)); _ = try await h.service.deliver(noteID: h.note.id)
        h.clock.set(Date(timeIntervalSince1970: 1_960)); _ = try await h.service.deliver(noteID: h.note.id)
        let retry = try await h.service.retry(noteID: h.note.id)
        let persisted = await h.store.note(id: h.note.id)!
        XCTAssertEqual(retry, .scheduled(Date(timeIntervalSince1970: 2_020)))
        XCTAssertEqual(persisted.delivery.failedAttempts.count, 4)
        XCTAssertEqual(persisted.delivery.currentRetryCycle, 1)
        XCTAssertEqual(persisted.delivery.status, .queued)
    }

    // Break: a stale crash-era active Attempt leaves the Note sending forever or blocks reconciliation.
    func testStaleAttemptBecomesBoundedFailureBeforeFreshWork() async throws {
        let h = try DeliveryHarness(responses: [.success(.init(statusCode: 204))])
        let stale = Attempt(noteID: h.note.id, configurationRevisionID: h.revision.id, device: .iphone,
            endpoint: h.revision.endpoint, startedAt: Date(timeIntervalSince1970: 800))
        await h.store.seed(.attemptStarted(stale))
        let reconciliation = try await h.service.deliver(noteID: h.note.id)
        h.clock.set(Date(timeIntervalSince1970: 1_060))
        let result = try await h.service.deliver(noteID: h.note.id)
        let delivery = await h.store.note(id: h.note.id)!.delivery
        XCTAssertEqual(reconciliation, .scheduled(Date(timeIntervalSince1970: 1_060)))
        XCTAssertEqual(result, .sent)
        XCTAssertEqual(delivery.failedAttempts.first?.attempt.id, stale.id)
        XCTAssertNotNil(delivery.receipt)
    }

    // Break: an offline launch leaves a crash-era Attempt sending forever or creates a new offline Attempt.
    func testOfflineLaunchReconcilesStaleAttemptWithoutStartingAnother() async throws {
        let h = try DeliveryHarness(connected: false)
        let stale = Attempt(noteID: h.note.id, configurationRevisionID: h.revision.id, device: .iphone,
            endpoint: h.revision.endpoint, startedAt: Date(timeIntervalSince1970: 800))
        await h.store.seed(.attemptStarted(stale))

        let result = try await h.service.deliver(noteID: h.note.id)
        let delivery = await h.store.note(id: h.note.id)!.delivery
        let requests = await h.fakeTransport.count()

        XCTAssertEqual(result, .queued)
        XCTAssertTrue(delivery.activeAttempts.isEmpty)
        XCTAssertEqual(delivery.failedAttempts.map(\.attempt.id), [stale.id])
        XCTAssertEqual(requests, 0)
    }
}

private final class MutableClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.withLock { value } }
    func set(_ value: Date) { lock.withLock { self.value = value } }
}

private actor TransportFake: HTTPTransport {
    private var responses: [Result<HTTPResponse, Error>]
    private(set) var requestCount = 0
    init(_ responses: [Result<HTTPResponse, Error>]) { self.responses = responses }
    func send(_ request: WebhookRequest) async throws -> HTTPResponse {
        requestCount += 1
        return try responses.removeFirst().get()
    }
    func count() -> Int { requestCount }
}

private actor TransportGate: HTTPTransport {
    private var continuation: CheckedContinuation<HTTPResponse, Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func send(_ request: WebhookRequest) async throws -> HTTPResponse {
        for waiter in waiters { waiter.resume() }; waiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func waitUntilCalled() async { if continuation != nil { return }; await withCheckedContinuation { waiters.append($0) } }
    func fail() { continuation?.resume(throwing: HTTPTransportError.network); continuation = nil }
}

private actor NotificationFake: DeliveryNotificationAdapter {
    private(set) var count = 0
    func notifyFailure(title: String, reason: String, noteID: NoteID) { count += 1 }
}

private actor SchedulerFake: DeliveryScheduler {
    typealias Operation = @Sendable () async -> Void
    private(set) var entries: [ScheduledDelivery] = []
    private var operations: [NoteID: Operation] = [:]
    func schedule(noteID: NoteID, earliest: Date, operation: @escaping @Sendable () async -> Void) {
        entries.append(.init(noteID: noteID, earliest: earliest))
        operations[noteID] = operation
    }
    func run(noteID: NoteID) async {
        let operation = operations.removeValue(forKey: noteID)
        await operation?()
    }
}

private actor ControlledDeliverySleeper: DeliverySleeper {
    private var continuations: [CheckedContinuation<Void, Error>] = []
    private var callWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requestedIntervals: [TimeInterval] = []

    func sleep(for interval: TimeInterval) async throws {
        requestedIntervals.append(interval)
        for waiter in callWaiters { waiter.resume() }
        callWaiters.removeAll()
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }

    func waitUntilCalled() async {
        if !requestedIntervals.isEmpty { return }
        await withCheckedContinuation { callWaiters.append($0) }
    }

    func resumeNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

private actor NoteIDRecorder {
    private(set) var values: [NoteID] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func append(_ value: NoteID) {
        values.append(value)
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
    func waitForCount(_ count: Int) async {
        if values.count >= count { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor DeliveryStoreFake: WhimStore {
    private var stored: Note
    private(set) var leaseHeld = false
    private(set) var leaseAcquireCount = 0
    private(set) var leaseOwners: [UUID] = []
    private var receiptOnAcquire = false
    private var notifiedCycles: Set<Int> = []
    init(note: Note) { stored = note }
    func seed(_ event: DeliveryEvent) { stored = replacing(delivery: DeliveryReducer.reduce(stored.delivery, event: event)) }
    func note(id: NoteID) -> Note? { id == stored.id ? stored : nil }
    func apply(_ event: DeliveryEvent, to noteID: NoteID) throws -> Delivery { seed(event); return stored.delivery }
    func acquireLease(_ kind: LeaseKind, noteID: NoteID, owner: UUID, until: Date) -> Bool {
        leaseAcquireCount += 1; leaseOwners.append(owner)
        if receiptOnAcquire {
            receiptOnAcquire = false
            let attempt = Attempt(noteID: stored.id, configurationRevisionID: ConfigurationRevisionID(),
                device: .iphone, endpoint: SanitizedEndpoint(scheme: "https", host: "other.example", path: "/"),
                startedAt: Date())
            seed(.receipt(.init(attemptID: attempt.id, noteID: stored.id, receivedAt: Date(), statusCode: 200)))
        }
        if leaseHeld { return false }; leaseHeld = true; return true
    }
    func releaseLease(_ kind: LeaseKind, noteID: NoteID, owner: UUID) { leaseHeld = false }
    func beginRetryCycle(noteID: NoteID) -> Bool {
        guard stored.delivery.receipt == nil else { return false }
        var delivery = stored.delivery; delivery.currentRetryCycle += 1; stored = replacing(delivery: delivery); return true
    }
    func markExhaustionNotified(noteID: NoteID, retryCycle: Int) -> Bool { notifiedCycles.insert(retryCycle).inserted }
    func setReceiptOnAcquire(_ value: Bool) { receiptOnAcquire = value }
    func isLeaseHeld() -> Bool { leaseHeld }
    private func replacing(delivery: Delivery) -> Note {
        Note(id: stored.id, recordingSessionID: stored.recordingSessionID, title: stored.title,
            titleSource: stored.titleSource, createdAt: stored.createdAt, duration: stored.duration,
            source: stored.source, captureOutcome: stored.captureOutcome, requiresReview: stored.requiresReview,
            audioURL: stored.audioURL, workflowID: stored.workflowID, delivery: delivery, localError: stored.localError)
    }
    func configurationRevision(for noteID: NoteID) -> ConfigurationRevision? { nil }
    func recordLocalError(_ error: LocalAudioError, noteID: NoteID) throws {
        stored = Note(id: stored.id, recordingSessionID: stored.recordingSessionID, title: stored.title,
            titleSource: stored.titleSource, createdAt: stored.createdAt, duration: stored.duration,
            source: stored.source, captureOutcome: stored.captureOutcome, requiresReview: stored.requiresReview,
            audioURL: stored.audioURL, workflowID: stored.workflowID, delivery: stored.delivery, localError: error)
    }
    func saveRecoveryError(_ recording: FinalizedRecording, error: LocalAudioError) throws {}
    func send(noteID: NoteID) throws {}
    func saveRecordingSession(_ session: RecordingSession) throws {}
    func recordingSessions() -> [RecordingSession] { [] }
    func discardRecordingSession(sessionID: RecordingSessionID) throws {}
    func recordSessionError(_ error: LocalAudioError, sessionID: RecordingSessionID) throws {}
    func delete(noteID: NoteID) throws {}
    func acknowledgeDeletion(noteID: NoteID, endpoint: AttemptDevice) throws {}
    func deletions() -> [DeletionTombstone] { [] }
    func saveConfigurationRevision(_ revision: ConfigurationRevision) throws {}
    func listNotes(filter: NoteFilter) -> [NoteProjection] { [NoteProjection(note: stored)] }
    func saveFinalized(_ finalized: FinalizedRecording) -> Note { stored }
    func updateTitle(noteID: NoteID, title: String, source: TitleSource) throws {}
}

private struct DeliveryHarness {
    let note: Note
    let revision: ConfigurationRevision
    let store: DeliveryStoreFake
    let transport: any HTTPTransport
    let fakeTransport: TransportFake
    let clock: MutableClock
    let notifications = NotificationFake()
    let service: DeliveryService

    init(connected: Bool = true, responses: [Result<HTTPResponse, Error>] = [], transport supplied: (any HTTPTransport)? = nil,
         scheduler: (any DeliveryScheduler)? = nil, writeAudio: Bool = true, device: AttemptDevice = .iphone) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audioURL = root.appendingPathComponent("note.m4a")
        if writeAudio { try Data("audio".utf8).write(to: audioURL) }
        note = Note(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "TITLE", titleSource: .timestamp,
            createdAt: Date(timeIntervalSince1970: 900), duration: 1, source: .iphone,
            captureOutcome: .completed, requiresReview: false, audioURL: audioURL,
            delivery: Delivery(hasUsableConfiguration: true))
        revision = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: Date(timeIntervalSince1970: 900),
            endpoint: SanitizedEndpoint(scheme: "https", host: "example.com", path: "/hook"))
        store = DeliveryStoreFake(note: note)
        let fakeTransport = TransportFake(responses)
        self.fakeTransport = fakeTransport
        self.transport = supplied ?? fakeTransport
        clock = MutableClock(Date(timeIntervalSince1970: 1_000))
        let credentialStore = CredentialFake(revision: revision.id, credentials: StoredWebhookCredentials(
            endpoint: URL(string: "https://example.com/hook?key=QUERY")!, bearerToken: "TOKEN", hmacSecret: nil,
            customHeaders: [.init(name: "X-Value", value: "HEADER")]))
        let selectedRevision = revision
        service = DeliveryService(store: store, credentials: credentialStore, transport: self.transport,
            notifications: notifications, clock: clock, scheduler: scheduler ?? SchedulerFake(), isConnected: { connected },
            configurationRevision: { _ in selectedRevision }, device: device, appVersion: "1", appBuild: "1")
    }
}

private actor CredentialFake: CredentialStore {
    let revision: ConfigurationRevisionID
    let value: StoredWebhookCredentials
    init(revision: ConfigurationRevisionID, credentials: StoredWebhookCredentials) { self.revision = revision; value = credentials }
    func save(_ credentials: StoredWebhookCredentials, for revisionID: ConfigurationRevisionID) throws {}
    func credentials(for revisionID: ConfigurationRevisionID) -> StoredWebhookCredentials? { revisionID == revision ? value : nil }
    func remove(for revisionID: ConfigurationRevisionID) throws {}
    func removeAll() throws {}
}
