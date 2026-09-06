import Foundation
import XCTest
@testable import WhimCore

final class TitleServiceTests: XCTestCase {
    // Break: enrichment stores the full transcript or keeps text after the first meaningful sentence.
    func testFirstMeaningfulSentenceIsCleanedAndOnlyTitleIsPersisted() async throws {
        let transcriber = TitleTranscriberFake(result: .success("  This   is the useful sentence.  This must not be retained."))
        let store = TitleStoreFake(note: fixtureNote())
        let service = TitleService(transcriber: transcriber, store: store,
            timestampTitle: { _ in "Sep 4, 2026 at 10:30" }, sleep: neverReachDeadline)

        let snapshot = await service.enrich(fixtureNote())
        let persistedTitle = await store.persistedTitle()

        XCTAssertEqual(snapshot.title, "This is the useful sentence.")
        XCTAssertEqual(snapshot.source, .transcription)
        XCTAssertEqual(persistedTitle, "This is the useful sentence.")
    }

    // Break: title truncation splits an extended grapheme cluster or retains more than 60 characters.
    func testTitleTruncatesAtSixtyUnicodeGraphemes() async throws {
        let transcript = String(repeating: "🧑🏽‍🚀", count: 59) + "é" + "z. Later."
        let transcriber = TitleTranscriberFake(result: .success(transcript))
        let store = TitleStoreFake(note: fixtureNote())
        let service = TitleService(transcriber: transcriber, store: store, sleep: neverReachDeadline)

        let snapshot = await service.enrich(fixtureNote())

        XCTAssertEqual(snapshot.title, String(repeating: "🧑🏽‍🚀", count: 59) + "é")
        XCTAssertEqual(snapshot.title.count, 60)
    }

    // Break: punctuation inside an abbreviation or decimal is mistaken for the end of the title sentence.
    func testSentenceSegmentationKeepsAbbreviationsAndDecimalsIntact() async throws {
        for (transcript, expected) in [
            ("Meet Dr. Smith tomorrow. Later sentence.", "Meet Dr. Smith tomorrow."),
            ("Version 1.2 ships Friday. Later sentence.", "Version 1.2 ships Friday."),
        ] {
            let note = fixtureNote()
            let service = TitleService(
                transcriber: TitleTranscriberFake(result: .success(transcript)),
                store: TitleStoreFake(note: note),
                sleep: neverReachDeadline
            )

            let snapshot = await service.enrich(note)

            XCTAssertEqual(snapshot.title, expected)
        }
    }

    // Break: unavailable, denied, failed, or empty recognition replaces the timestamp fallback.
    func testRecognitionFailuresAndEmptyResultsUseTimestampFallback() async throws {
        for result in [
            Result<String, Error>.failure(TranscriptionError.unavailable),
            .failure(TranscriptionError.notAuthorized),
            .failure(TitleTestError.failed),
            .success(" \n\t "),
        ] {
            let note = fixtureNote()
            let service = TitleService(transcriber: TitleTranscriberFake(result: result),
                store: TitleStoreFake(note: note), timestampTitle: { _ in "Sep 4, 2026 at 10:30" },
                sleep: neverReachDeadline)

            let snapshot = await service.enrich(note)

            XCTAssertEqual(snapshot.title, "Sep 4, 2026 at 10:30")
            XCTAssertEqual(snapshot.source, .timestamp)
        }
    }

    // Break: a late transcript mutates the already-produced delivery title or is discarded locally.
    func testLateTitlePersistsLocallyWithoutMutatingDeadlineSnapshot() async throws {
        let note = fixtureNote()
        let transcriber = SuspendedTranscriber()
        let sleeper = ControlledSleeper()
        let store = TitleStoreFake(note: note)
        let service = TitleService(transcriber: transcriber, store: store,
            timestampTitle: { _ in "Sep 4, 2026 at 10:30" }, sleep: { duration in try await sleeper.sleep(duration) })
        let enriching = Task { await service.enrich(note) }
        await transcriber.waitUntilStarted()
        await sleeper.waitUntilStarted()

        await sleeper.release()
        let deliverySnapshot = await enriching.value
        await transcriber.complete(with: "A later local title. Full transcript is discarded.")
        await store.waitForTitleUpdate()
        let persistedTitle = await store.persistedTitle()
        let requestedDuration = await sleeper.requestedDuration()

        XCTAssertEqual(deliverySnapshot.title, "Sep 4, 2026 at 10:30")
        XCTAssertEqual(deliverySnapshot.source, .timestamp)
        XCTAssertEqual(persistedTitle, "A later local title.")
        XCTAssertEqual(requestedDuration, .milliseconds(300))
    }

    // Break: delivery joining an already-running title job starts a second transcription.
    func testConcurrentSnapshotCallersShareOneTitleJob() async {
        let note = fixtureNote()
        let transcriber = DedupeTranscriber()
        let service = TitleService(transcriber: transcriber, store: TitleStoreFake(note: note),
            sleep: neverReachDeadline)
        let first = Task { await service.enrich(note) }
        await transcriber.waitUntilStarted()
        let second = Task { await service.enrich(note) }
        for _ in 0..<100 { await Task.yield() }
        let startsBeforeRelease = await transcriber.startCount
        await transcriber.release(with: "Shared title.")
        let values = await [first.value, second.value]

        XCTAssertEqual(startsBeforeRelease, 1)
        XCTAssertEqual(values.map(\.title), ["Shared title.", "Shared title."])
    }
}

private func fixtureNote() -> Note {
    Note(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Sep 4, 2026 at 10:30",
        titleSource: .timestamp, createdAt: Date(timeIntervalSince1970: 1_788_534_600), duration: 3,
        source: .iphone, captureOutcome: .completed, requiresReview: false,
        audioURL: URL(fileURLWithPath: "/notes/fixture.m4a"))
}

private enum TitleTestError: Error { case failed }

private func neverReachDeadline(_ duration: Duration) async throws {
    try await Task.sleep(for: .seconds(60))
}

private struct TitleTranscriberFake: Transcriber {
    let result: Result<String, Error>
    func transcribe(audioAt url: URL, locale: Locale) async throws -> String { try result.get() }
}

private actor SuspendedTranscriber: Transcriber {
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultWaiter: CheckedContinuation<String, Error>?

    func transcribe(audioAt url: URL, locale: Locale) async throws -> String {
        started = true
        for waiter in startedWaiters { waiter.resume() }
        startedWaiters.removeAll()
        return try await withCheckedThrowingContinuation { resultWaiter = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func complete(with transcript: String) {
        resultWaiter?.resume(returning: transcript)
        resultWaiter = nil
    }
}

private actor DedupeTranscriber: Transcriber {
    private(set) var startCount = 0
    private var resolved: String?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultWaiters: [CheckedContinuation<String, Never>] = []

    func transcribe(audioAt url: URL, locale: Locale) async throws -> String {
        startCount += 1
        if let resolved { return resolved }
        for waiter in startedWaiters { waiter.resume() }
        startedWaiters.removeAll()
        return await withCheckedContinuation { resultWaiters.append($0) }
    }

    func waitUntilStarted() async {
        if startCount > 0 { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func release(with result: String) {
        resolved = result
        for waiter in resultWaiters { waiter.resume(returning: result) }
        resultWaiters.removeAll()
    }
}

private actor ControlledSleeper {
    private var duration: Duration?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var sleepWaiter: CheckedContinuation<Void, Error>?

    func sleep(_ duration: Duration) async throws {
        self.duration = duration
        for waiter in startedWaiters { waiter.resume() }
        startedWaiters.removeAll()
        try await withCheckedThrowingContinuation { sleepWaiter = $0 }
    }

    func waitUntilStarted() async {
        if duration != nil { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func release() {
        sleepWaiter?.resume()
        sleepWaiter = nil
    }

    func requestedDuration() -> Duration? { duration }
}

private actor TitleStoreFake: WhimStore {
    private var storedNote: Note
    private var titleUpdateWaiters: [CheckedContinuation<Void, Never>] = []

    init(note: Note) { storedNote = note }

    func persistedTitle() -> String { storedNote.title }
    func waitForTitleUpdate() async {
        if storedNote.titleSource == .transcription { return }
        await withCheckedContinuation { titleUpdateWaiters.append($0) }
    }
    func updateTitle(noteID: NoteID, title: String, source: TitleSource) async throws {
        storedNote = Note(id: storedNote.id, recordingSessionID: storedNote.recordingSessionID,
            title: title, titleSource: source, createdAt: storedNote.createdAt, duration: storedNote.duration,
            source: storedNote.source, captureOutcome: storedNote.captureOutcome,
            requiresReview: storedNote.requiresReview, audioURL: storedNote.audioURL,
            workflowID: storedNote.workflowID, delivery: storedNote.delivery, localError: storedNote.localError)
        for waiter in titleUpdateWaiters { waiter.resume() }
        titleUpdateWaiters.removeAll()
    }

    func recordLocalError(_ error: LocalAudioError, noteID: NoteID) async throws {}
    func saveRecoveryError(_ recording: FinalizedRecording, error: LocalAudioError) async throws {}
    func send(noteID: NoteID) async throws {}
    func saveRecordingSession(_ session: RecordingSession) async throws {}
    func recordingSessions() async throws -> [RecordingSession] { [] }
    func discardRecordingSession(sessionID: RecordingSessionID) async throws {}
    func recordSessionError(_ error: LocalAudioError, sessionID: RecordingSessionID) async throws {}
    func delete(noteID: NoteID) async throws {}
    func acknowledgeDeletion(noteID: NoteID, endpoint: AttemptDevice) async throws {}
    func deletions() async throws -> [DeletionTombstone] { [] }
    func saveConfigurationRevision(_ revision: ConfigurationRevision) async throws {}
    func configurationRevision(for noteID: NoteID) async throws -> ConfigurationRevision? { nil }
    func note(id: NoteID) async throws -> Note? { id == storedNote.id ? storedNote : nil }
    func listNotes(filter: NoteFilter) async throws -> [NoteProjection] { [] }
    func saveFinalized(_ finalized: FinalizedRecording) async throws -> Note { storedNote }
    func apply(_ event: DeliveryEvent, to noteID: NoteID) async throws -> Delivery { storedNote.delivery }
    func acquireLease(_ kind: LeaseKind, noteID: NoteID, owner: UUID, until: Date) async throws -> Bool { false }
    func releaseLease(_ kind: LeaseKind, noteID: NoteID, owner: UUID) async throws {}
}
