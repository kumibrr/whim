import Foundation
import XCTest
@testable import WhimCore

final class RecordingServiceTests: XCTestCase {
    // Break: a second Record invocation creates another Recording Session instead of focusing the active one.
    func testSecondStartFocusesExistingRecording() async throws {
        let harness = RecordingHarness()

        let first = try await harness.service.start(source: .iphone)
        let second = try await harness.service.start(source: .iphone)
        let startCount = await harness.recorder.startCount
        let savedSessionCount = await harness.store.savedSessions.count

        XCTAssertEqual(second.sessionID, first.sessionID)
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(savedSessionCount, 1)
    }

    // Break: Stop closes capture but never turns the active Recording Session into a completed Note.
    func testStopProducesCompletedNote() async throws {
        let harness = RecordingHarness()
        _ = try await harness.service.start(source: .iphone)
        await harness.recorder.completeOnStop(duration: 12, peakPowerDBFS: -20)

        let note = try await harness.service.stop()

        XCTAssertEqual(note?.duration, 12)
        XCTAssertEqual(note?.captureOutcome, .completed)
        XCTAssertEqual(note?.source, .iphone)
        XCTAssertEqual(note?.titleSource, .timestamp)
    }

    // Break: Discard leaves the unfinished database row or temporary audio available for recovery.
    func testDiscardDeletesRecordingSessionAndTemporaryAudio() async throws {
        let harness = RecordingHarness()
        let snapshot = try await harness.service.start(source: .iphone)

        try await harness.service.discard()

        let sessions = await harness.store.savedSessions
        let note = try await harness.store.note(id: snapshot.noteID)
        XCTAssertTrue(sessions.isEmpty)
        XCTAssertEqual(harness.files.deletedTemporaryIDs(), [snapshot.sessionID])
        XCTAssertNil(note)
    }

    // Break: microphone activation failure leaves a recoverable session or creates a Note for audio that never started.
    func testActivationFailureCreatesNoNoteAndCleansSession() async throws {
        let harness = RecordingHarness()
        await harness.recorder.failActivation()

        do {
            _ = try await harness.service.start(source: .iphone)
            XCTFail("Activation failure was accepted")
        } catch RecordingTestError.activationFailed { }

        let sessions = await harness.store.savedSessions
        let notes = await harness.store.noteCount
        XCTAssertTrue(sessions.isEmpty)
        XCTAssertEqual(notes, 0)
        XCTAssertEqual(harness.files.deletedTemporaryIDs().count, 1)
    }

    // Break: an audio interruption abandons playable audio or records it as an ordinary completed capture.
    func testInterruptionFinalizesPlayableAudioAsInterruptedNote() async throws {
        let harness = RecordingHarness()
        _ = try await harness.service.start(source: .iphone)
        await harness.recorder.completeOnStop(duration: 3, peakPowerDBFS: -25)
        harness.files.setFinalizedDuration(3)

        let note = try await harness.service.handleInterruption()

        XCTAssertEqual(note?.captureOutcome, .interrupted)
        XCTAssertEqual(note?.duration, 3)
    }

    // Break: sub-second silence becomes a durable Note instead of being automatically discarded.
    func testShortSilentRecordingIsAutomaticallyDiscarded() async throws {
        let harness = RecordingHarness()
        let snapshot = try await harness.service.start(source: .iphone)
        await harness.recorder.completeOnStop(duration: 0.5, peakPowerDBFS: -50)

        let note = try await harness.service.stop()
        let sessions = await harness.store.savedSessions

        XCTAssertNil(note)
        XCTAssertEqual(harness.files.deletedTemporaryIDs(), [snapshot.sessionID])
        XCTAssertTrue(sessions.isEmpty)
    }

    // Break: either sub-second meaningful speech or one-second silence is discarded when only one discard condition matches.
    func testPlayableAudioIsPreservedUnlessBothDiscardConditionsHold() async throws {
        let meaningful = RecordingHarness()
        _ = try await meaningful.service.start(source: .iphone)
        await meaningful.recorder.completeOnStop(duration: 0.5, peakPowerDBFS: -44)
        meaningful.files.setFinalizedDuration(0.5)
        let meaningfulNote = try await meaningful.service.stop()

        let longEnough = RecordingHarness()
        _ = try await longEnough.service.start(source: .iphone)
        await longEnough.recorder.completeOnStop(duration: 1, peakPowerDBFS: -60)
        longEnough.files.setFinalizedDuration(1)
        let longEnoughNote = try await longEnough.service.stop()

        XCTAssertEqual(meaningfulNote?.duration, 0.5)
        XCTAssertEqual(longEnoughNote?.duration, 1)
    }

    // Break: a concurrent caller reports a successful start while the shared persistence/activation boundary later fails.
    func testConcurrentStartsShareTheInFlightResult() async throws {
        let harness = RecordingHarness()
        await harness.store.suspendSessionSave(failing: true)
        let first = Task { try await harness.service.start(source: .iphone) }
        await harness.store.waitUntilSessionSaveStarts()
        let second = Task { try await harness.service.start(source: .iphone) }
        await harness.store.releaseSessionSave()

        let results = await [first.result, second.result]
        let startCount = await harness.recorder.startCount
        let sessions = await harness.store.savedSessions

        XCTAssertEqual(results.compactMap { try? $0.get() }.count, 0)
        XCTAssertEqual(startCount, 0)
        XCTAssertTrue(sessions.isEmpty)
    }

    // Break: Stop races past an in-flight start and reports no Note even though capture activates afterward.
    func testStopWaitsForInFlightStartThenFinalizesIt() async throws {
        let harness = RecordingHarness()
        await harness.store.suspendSessionSave(failing: false)
        await harness.recorder.completeOnStop(duration: 4, peakPowerDBFS: -20)
        harness.files.setFinalizedDuration(4)
        let starting = Task { try await harness.service.start(source: .iphone) }
        await harness.store.waitUntilSessionSaveStarts()

        let stopping = Task { try await harness.service.stop() }
        await harness.store.releaseSessionSave()

        _ = try await starting.value
        let note = try await stopping.value
        let stopCount = await harness.recorder.stopCount
        XCTAssertEqual(note?.duration, 4)
        XCTAssertEqual(stopCount, 1)
    }

    // Break: Discard races past activation and leaves the newly active session behind.
    func testDiscardWaitsForInFlightStartThenDeletesSessionAndFile() async throws {
        let harness = RecordingHarness()
        await harness.store.suspendSessionSave(failing: false)
        let starting = Task { try await harness.service.start(source: .iphone) }
        await harness.store.waitUntilSessionSaveStarts()

        let discarding = Task { try await harness.service.discard() }
        await harness.store.releaseSessionSave()

        let snapshot = try await starting.value
        try await discarding.value
        let sessions = await harness.store.savedSessions
        XCTAssertEqual(harness.files.deletedTemporaryIDs(), [snapshot.sessionID])
        XCTAssertTrue(sessions.isEmpty)
    }

    // Break: Discard clears the active session before hardware cleanup, allowing a new capture to overlap it.
    func testNewStartWaitsForInFlightHardwareDiscard() async throws {
        let harness = RecordingHarness()
        let first = try await harness.service.start(source: .iphone)
        await harness.recorder.suspendDiscard()
        let discarding = Task { try await harness.service.discard() }
        await harness.recorder.waitUntilDiscardStarts()

        let overlap = expectation(description: "a second recorder start overlaps discard")
        overlap.isInverted = true
        await harness.recorder.observeSecondStart { overlap.fulfill() }
        let driver = RecordingStartDriver()
        let starting = Task { try await driver.start(harness.service) }
        await driver.waitUntilCallStarts()
        await fulfillment(of: [overlap], timeout: 0.1)
        await harness.recorder.observeSecondStart(nil)

        let startsDuringDiscard = await harness.recorder.startCount
        XCTAssertEqual(startsDuringDiscard, 1)
        await harness.recorder.releaseDiscard()
        try await discarding.value
        let second = try await starting.value
        XCTAssertNotEqual(second.sessionID, first.sessionID)
        let totalStarts = await harness.recorder.startCount
        XCTAssertEqual(totalStarts, 2)
    }

    // Break: Encoder completion emitted synchronously by hardware activation is dropped, so Stop uses stale/later data.
    func testEncoderCompletionDuringActivationIsPreserved() async throws {
        let harness = RecordingHarness()
        let events = await harness.service.events()
        await harness.recorder.suspendStart(afterEmitting: [
            .encoderCompleted(duration: 0.5, peakPowerDBFS: -60),
            .peakPower(-60),
        ])
        await harness.recorder.completeOnStop(duration: 4, peakPowerDBFS: -20)
        let starting = Task { try await harness.service.start(source: .iphone) }
        await harness.recorder.waitUntilStartEventsAreEmitted()
        await assertNextEvent(.peakPower(-60), from: events)
        await harness.recorder.releaseStart()
        _ = try await starting.value

        let note = try await harness.service.stop()
        let stopCount = await harness.recorder.stopCount

        XCTAssertNil(note)
        XCTAssertEqual(stopCount, 0)
    }

    // Break: Encoder failure emitted synchronously by hardware activation is dropped, leaving false success or a hung Stop.
    func testEncoderFailureDuringActivationIsPreserved() async throws {
        let harness = RecordingHarness()
        let events = await harness.service.events()
        await harness.recorder.suspendStart(afterEmitting: [.failure, .peakPower(-60)])
        await harness.recorder.completeOnStop(duration: 4, peakPowerDBFS: -20)
        let starting = Task { try await harness.service.start(source: .iphone) }
        await harness.recorder.waitUntilStartEventsAreEmitted()
        await assertNextEvent(.peakPower(-60), from: events)
        await harness.recorder.releaseStart()
        let snapshot = try await starting.value

        do { _ = try await harness.service.stop(); XCTFail("Activation-time encoder failure was ignored") }
        catch RecordingServiceError.encoderFailed { }
        let sessionError = await harness.store.sessionError(id: snapshot.sessionID)
        let stopCount = await harness.recorder.stopCount
        let discardCount = await harness.recorder.discardCount
        XCTAssertEqual(sessionError, .unreadable)
        XCTAssertEqual(stopCount, 0)
        XCTAssertEqual(discardCount, 1)
    }

    // Break: An interruption delivered while the microphone is activating is ignored instead of finalizing safely.
    func testInterruptionDuringActivationFinalizesOnce() async throws {
        let harness = RecordingHarness()
        let events = await harness.service.events()
        await harness.recorder.suspendStart(afterEmitting: [.interruption, .peakPower(-30)])
        await harness.recorder.completeOnStop(duration: 3, peakPowerDBFS: -20)
        harness.files.setFinalizedDuration(3)
        let starting = Task { try await harness.service.start(source: .iphone) }
        await harness.recorder.waitUntilStartEventsAreEmitted()
        await assertNextEvent(.peakPower(-30), from: events)
        await harness.recorder.releaseStart()
        _ = try await starting.value

        await harness.store.waitUntilNoteIsSaved()

        let note = await harness.store.firstNote()
        let stopCount = await harness.recorder.stopCount
        XCTAssertEqual(note?.captureOutcome, .interrupted)
        XCTAssertEqual(stopCount, 1)
    }

    // Break: overlapping Stop and interruption calls close the encoder twice or create two Notes.
    func testOverlappingStopAndInterruptionShareOneFinalization() async throws {
        let harness = RecordingHarness()
        _ = try await harness.service.start(source: .iphone)
        let stopping = Task { try await harness.service.stop() }
        await harness.recorder.waitUntilStopStarts()
        let interrupted = Task { try await harness.service.handleInterruption() }

        await harness.recorder.emit(.encoderCompleted(duration: 8, peakPowerDBFS: -20))

        let first = try await stopping.value
        let second = try await interrupted.value
        let stopCount = await harness.recorder.readStopCount()
        let noteCount = await harness.store.noteCount
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(first?.captureOutcome, .completed)
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(noteCount, 1)
    }

    // Break: an encoder failure leaves Stop suspended forever with an invisible unfinished session.
    func testEncoderFailureResumesStopWithRecoverableError() async throws {
        let harness = RecordingHarness()
        let snapshot = try await harness.service.start(source: .iphone)
        let stopping = Task { try await harness.service.stop() }
        await harness.recorder.waitUntilStopStarts()

        await harness.recorder.emit(.failure)

        do { _ = try await stopping.value; XCTFail("Encoder failure was accepted") }
        catch RecordingServiceError.encoderFailed { }
        let error = await harness.store.sessionError(id: snapshot.sessionID)
        let noteCount = await harness.store.noteCount
        XCTAssertEqual(error, .unreadable)
        XCTAssertEqual(noteCount, 0)
    }

    // Break: termination of the recorder event stream abandons the encoder continuation forever.
    func testEventStreamTerminationResumesStopWithRecoverableError() async throws {
        let harness = RecordingHarness()
        let snapshot = try await harness.service.start(source: .iphone)
        let stopping = Task { try await harness.service.stop() }
        await harness.recorder.waitUntilStopStarts()

        await harness.recorder.finishEvents()

        do { _ = try await stopping.value; XCTFail("Terminated stream was accepted") }
        catch RecordingServiceError.eventStreamEnded { }
        let error = await harness.store.sessionError(id: snapshot.sessionID)
        XCTAssertEqual(error, .unreadable)
    }

    // Break: threshold events warn repeatedly or allow capture past the five-minute limit.
    func testWarningAt285AndAutomaticStopAt300OccurExactlyOnce() async throws {
        let harness = RecordingHarness()
        let events = await harness.service.events()
        _ = try await harness.service.start(source: .iphone)
        await harness.recorder.completeOnStop(duration: 300, peakPowerDBFS: -20)

        await harness.recorder.emit(.elapsed(284))
        await harness.recorder.emit(.elapsed(285))
        await harness.recorder.emit(.elapsed(286))
        await harness.recorder.emit(.elapsed(300))

        var iterator = events.makeAsyncIterator()
        var received: [RecordingServiceEvent] = []
        for _ in 0..<5 { if let event = await iterator.next() { received.append(event) } }
        await harness.recorder.waitUntilStopStarts()
        await harness.store.waitUntilNoteIsSaved()
        await harness.recorder.emit(.elapsed(301))

        let stopCount = await harness.recorder.readStopCount()
        let noteCount = await harness.store.noteCount
        XCTAssertEqual(received.filter { $0 == .maximumDurationWarning }.count, 1)
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(noteCount, 1)
    }

    // Break: consumer projections omit live metering or route changes needed by recorder surfaces.
    func testProgressAndRouteEventsAreProjectedForConsumers() async throws {
        let harness = RecordingHarness()
        let events = await harness.service.events()
        _ = try await harness.service.start(source: .iphone)

        await harness.recorder.emit(.elapsed(1))
        await harness.recorder.emit(.peakPower(-22))
        await harness.recorder.emit(.routeChanged)
        await harness.recorder.emit(.elapsed(2))

        var iterator = events.makeAsyncIterator()
        var received: [RecordingServiceEvent] = []
        for _ in 0..<3 { if let event = await iterator.next() { received.append(event) } }
        XCTAssertEqual(received, [.elapsed(1), .peakPower(-22), .routeChanged])
    }

    // Break: the exact meaningful-power boundary is treated as exceeding the threshold.
    func testExactSilenceThresholdIsDiscardedWhenShorterThanOneSecond() async throws {
        let harness = RecordingHarness()
        _ = try await harness.service.start(source: .iphone)
        await harness.recorder.completeOnStop(duration: 0.999, peakPowerDBFS: -45)

        let note = try await harness.service.stop()
        XCTAssertNil(note)
    }

    private func assertNextEvent(_ expected: RecordingServiceEvent,
        from events: AsyncStream<RecordingServiceEvent>, file: StaticString = #filePath, line: UInt = #line) async {
        let received = expectation(description: "receive activation-time recorder event")
        let reading = Task {
            var iterator = events.makeAsyncIterator()
            let event = await iterator.next()
            XCTAssertEqual(event, expected, file: file, line: line)
            received.fulfill()
        }
        await fulfillment(of: [received], timeout: 0.5)
        reading.cancel()
    }
}

private struct RecordingHarness {
    let recorder = RecordingRecorderFake()
    let store = RecordingStoreFake()
    let files = RecordingFilesFake()
    let service: RecordingService

    init() {
        service = RecordingService(recorder: recorder, store: store, files: files)
    }
}

private actor RecordingRecorderFake: AudioRecorder {
    private let stream: AsyncStream<RecordingEvent>
    private let continuation: AsyncStream<RecordingEvent>.Continuation
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var discardCount = 0
    private var stopResult: (TimeInterval, Float)?
    private var activationFails = false
    private var stopStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var startEvents: [RecordingEvent] = []
    private var shouldSuspendStart = false
    private var startEventsWereEmitted = false
    private var startEventsWaiters: [CheckedContinuation<Void, Never>] = []
    private var startReleaseWaiter: CheckedContinuation<Void, Never>?
    private var shouldSuspendDiscard = false
    private var discardHasStarted = false
    private var discardStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var discardReleaseWaiter: CheckedContinuation<Void, Never>?
    private var secondStartObserver: (@Sendable () -> Void)?

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: RecordingEvent.self)
    }

    func events() -> AsyncStream<RecordingEvent> { stream }
    func start(at url: URL) async throws {
        startCount += 1
        if startCount == 2 { secondStartObserver?() }
        if activationFails { throw RecordingTestError.activationFailed }
        for event in startEvents { continuation.yield(event) }
        if shouldSuspendStart {
            startEventsWereEmitted = true
            for waiter in startEventsWaiters { waiter.resume() }
            startEventsWaiters.removeAll()
            await withCheckedContinuation { startReleaseWaiter = $0 }
        }
    }
    func stop() async throws {
        stopCount += 1
        for waiter in stopStartedWaiters { waiter.resume() }
        stopStartedWaiters.removeAll()
        if let stopResult {
            continuation.yield(.encoderCompleted(duration: stopResult.0, peakPowerDBFS: stopResult.1))
        }
    }
    func discard() async {
        discardCount += 1
        guard shouldSuspendDiscard else { return }
        discardHasStarted = true
        for waiter in discardStartedWaiters { waiter.resume() }
        discardStartedWaiters.removeAll()
        await withCheckedContinuation { discardReleaseWaiter = $0 }
    }
    func completeOnStop(duration: TimeInterval, peakPowerDBFS: Float) {
        stopResult = (duration, peakPowerDBFS)
    }
    func failActivation() { activationFails = true }
    func emit(_ event: RecordingEvent) { continuation.yield(event) }
    func finishEvents() { continuation.finish() }
    func readStopCount() -> Int { stopCount }
    func waitUntilStopStarts() async {
        if stopCount > 0 { return }
        await withCheckedContinuation { stopStartedWaiters.append($0) }
    }
    func suspendStart(afterEmitting events: [RecordingEvent]) {
        startEvents = events
        shouldSuspendStart = true
    }
    func waitUntilStartEventsAreEmitted() async {
        if startEventsWereEmitted { return }
        await withCheckedContinuation { startEventsWaiters.append($0) }
    }
    func releaseStart() {
        startReleaseWaiter?.resume()
        startReleaseWaiter = nil
        shouldSuspendStart = false
    }
    func suspendDiscard() { shouldSuspendDiscard = true }
    func waitUntilDiscardStarts() async {
        if discardHasStarted { return }
        await withCheckedContinuation { discardStartedWaiters.append($0) }
    }
    func releaseDiscard() {
        discardReleaseWaiter?.resume()
        discardReleaseWaiter = nil
        shouldSuspendDiscard = false
    }
    func observeSecondStart(_ observer: (@Sendable () -> Void)?) { secondStartObserver = observer }
}

private enum RecordingTestError: Error { case activationFailed }

private actor RecordingStoreFake: WhimStore {
    private(set) var savedSessions: [RecordingSession] = []
    private var notes: [NoteID: Note] = [:]
    var noteCount: Int { notes.count }
    private var shouldSuspendSave = false
    private var suspendedSaveFails = false
    private var saveHasStarted = false
    private var saveStartedWaiter: CheckedContinuation<Void, Never>?
    private var saveReleaseWaiter: CheckedContinuation<Void, Never>?
    private var noteSavedWaiters: [CheckedContinuation<Void, Never>] = []

    func saveRecordingSession(_ session: RecordingSession) async throws {
        if shouldSuspendSave {
            saveHasStarted = true
            saveStartedWaiter?.resume()
            saveStartedWaiter = nil
            await withCheckedContinuation { saveReleaseWaiter = $0 }
            if suspendedSaveFails { throw RecordingTestError.activationFailed }
        }
        savedSessions.append(session)
    }
    func recordingSessions() async throws -> [RecordingSession] { savedSessions }
    func recordSessionError(_ error: LocalAudioError, sessionID: RecordingSessionID) async throws {
        guard let index = savedSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        savedSessions[index].localError = error
    }
    func discardRecordingSession(sessionID: RecordingSessionID) async throws {
        savedSessions.removeAll { $0.id == sessionID }
    }
    func recordLocalError(_ error: LocalAudioError, noteID: NoteID) async throws {}
    func saveRecoveryError(_ recording: FinalizedRecording, error: LocalAudioError) async throws {}
    func send(noteID: NoteID) async throws {}
    func delete(noteID: NoteID) async throws {}
    func acknowledgeDeletion(noteID: NoteID, endpoint: AttemptDevice) async throws {}
    func deletions() async throws -> [DeletionTombstone] { [] }
    func saveConfigurationRevision(_ revision: ConfigurationRevision) async throws {}
    func configurationRevision(for noteID: NoteID) async throws -> ConfigurationRevision? { nil }
    func note(id: NoteID) async throws -> Note? { notes[id] }
    func listNotes(filter: NoteFilter) async throws -> [NoteProjection] { [] }
    func saveFinalized(_ finalized: FinalizedRecording) async throws -> Note {
        let note = Note(id: finalized.id, recordingSessionID: finalized.recordingSessionID,
            title: finalized.title, titleSource: finalized.titleSource, createdAt: finalized.createdAt,
            duration: finalized.duration, source: finalized.source, captureOutcome: finalized.captureOutcome,
            requiresReview: finalized.requiresReview, audioURL: finalized.audioURL)
        notes[note.id] = note
        savedSessions.removeAll { $0.id == finalized.recordingSessionID }
        for waiter in noteSavedWaiters { waiter.resume() }
        noteSavedWaiters.removeAll()
        return note
    }
    func apply(_ event: DeliveryEvent, to noteID: NoteID) async throws -> Delivery { .pending }
    func acquireLease(_ kind: LeaseKind, noteID: NoteID, owner: UUID, until: Date) async throws -> Bool { false }
    func releaseLease(_ kind: LeaseKind, noteID: NoteID, owner: UUID) async throws {}
    func updateTitle(noteID: NoteID, title: String, source: TitleSource) async throws {}

    func suspendSessionSave(failing: Bool) {
        shouldSuspendSave = true
        suspendedSaveFails = failing
    }
    func waitUntilSessionSaveStarts() async {
        if saveHasStarted { return }
        await withCheckedContinuation { saveStartedWaiter = $0 }
    }
    func releaseSessionSave() {
        saveReleaseWaiter?.resume()
        saveReleaseWaiter = nil
    }
    func sessionError(id: RecordingSessionID) -> LocalAudioError? {
        savedSessions.first { $0.id == id }?.localError
    }
    func waitUntilNoteIsSaved() async {
        if !notes.isEmpty { return }
        await withCheckedContinuation { noteSavedWaiters.append($0) }
    }
    func firstNote() -> Note? { notes.values.first }
}

private actor RecordingStartDriver {
    private var callStarted = false
    private var callStartedWaiter: CheckedContinuation<Void, Never>?

    func start(_ service: RecordingService) async throws -> RecordingSnapshot {
        callStarted = true
        callStartedWaiter?.resume()
        callStartedWaiter = nil
        return try await service.start(source: .iphone)
    }

    func waitUntilCallStarts() async {
        if callStarted { return }
        await withCheckedContinuation { callStartedWaiter = $0 }
    }
}

private final class RecordingFilesFake: AudioFileManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var deleted: [RecordingSessionID] = []
    private var finalizedDuration: TimeInterval = 12

    func deleteTemporary(sessionID: RecordingSessionID) throws {
        lock.withLock { deleted.append(sessionID) }
    }
    func deletedTemporaryIDs() -> [RecordingSessionID] { lock.withLock { deleted } }
    func setFinalizedDuration(_ duration: TimeInterval) { lock.withLock { finalizedDuration = duration } }
    func audioError(at url: URL) -> LocalAudioError? { nil }
    func durableNoteIDs() throws -> [NoteID] { [] }
    func durableAudio(noteID: NoteID) throws -> FinalizedAudio? { nil }
    func audioURL(for noteID: NoteID) -> URL { URL(fileURLWithPath: "/notes/\(noteID.rawValue).m4a") }
    func temporaryURL(for sessionID: RecordingSessionID) throws -> URL { URL(fileURLWithPath: "/tmp/\(sessionID.rawValue).m4a") }
    func finalize(sessionID: RecordingSessionID, noteID: NoteID) throws -> FinalizedAudio {
        FinalizedAudio(url: audioURL(for: noteID), duration: lock.withLock { finalizedDuration },
            createdAt: Date(timeIntervalSince1970: 1_788_534_600))
    }
    func makeDeliveredProtectionStrict(noteID: NoteID) throws {}
    func delete(noteID: NoteID) throws {}
    func playablePartial(sessionID: RecordingSessionID) throws -> PartialAudio? { nil }
}
