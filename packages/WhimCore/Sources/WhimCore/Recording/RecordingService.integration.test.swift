import AVFoundation
import Foundation
import XCTest
@testable import WhimCore

final class RecordingServiceIntegrationTests: XCTestCase {
    #if DEBUG
    func testCaptureLatencyRecordsInvocationAndDurableSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteWhimStore.open(at: root.appendingPathComponent("whim.sqlite"))
        let files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        let service = RecordingService(recorder: FixtureAudioRecorder(), store: store, files: files)
        _ = try await service.start(source: .iphone)
        let first = CaptureLatencyProbe.shared.snapshot()
        let invocation = try XCTUnwrap(first[.invocationReceived])
        let persisted = try XCTUnwrap(first[.sessionPersisted])
        XCTAssertLessThanOrEqual(invocation, persisted)
        _ = try await service.start(source: .iphone)
        XCTAssertEqual(CaptureLatencyProbe.shared.snapshot(), first)
        try await service.discard()
    }
    #endif

    // Break: a second composition recovers a Recording Session whose writer is still alive.
    func testRecoveryDoesNotTouchAnotherLiveRecorder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("whim.sqlite")
        let store = try SQLiteWhimStore.open(at: database)
        let files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        let service = RecordingService(recorder: FixtureAudioRecorder(), store: store, files: files)
        let session = try await service.start(source: .iphone)
        let reopened = try SQLiteWhimStore.open(at: database)
        let otherFiles = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        try await RecoveryScanner(store: reopened, files: otherFiles).scan()
        let recovered = try await reopened.note(id: session.noteID)
        XCTAssertNil(recovered, "Live audio must not be finalized as crash recovery")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try files.temporaryURL(for: session.sessionID).path))
        let saved = try await service.stop()
        XCTAssertEqual(saved?.captureOutcome, .completed)
    }

    // Break: the Island remains static because microphone measurements never reach its activity.
    func testMicrophoneSignalReachesTheActiveLiveActivity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteWhimStore.open(at: root.appendingPathComponent("whim.sqlite"))
        let files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        let recorder = FixtureAudioRecorder()
        let system = SignalActivitySystem()
        let service = RecordingService(recorder: recorder, store: store, files: files,
            activity: LiveActivityAdapter(system: system))
        let events = await service.events()
        let session = try await service.start(source: .iphone)
        let signal = RecordingSignal(peakPowerDBFS: -12, tone: 0.75)
        await recorder.emit(.signal(signal))
        await recorder.emit(.routeChanged)
        var iterator = events.makeAsyncIterator()
        _ = await iterator.next()
        _ = await iterator.next()
        await system.waitForMeasurement()
        let measurements = await system.measurements
        let sessions = await system.updatedSessions
        XCTAssertEqual(measurements, [signal])
        XCTAssertEqual(sessions, [session.sessionID])
        _ = try await service.stop()
    }

    // Break: a slow ActivityKit update holds encoder completion and interruptions behind it.
    func testStopAndInterruptionFinalizeWhileActivityPublicationIsSuspended() async throws {
        for interrupted in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try SQLiteWhimStore.open(at: root.appendingPathComponent("whim.sqlite"))
            let files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
            let recorder = FixtureAudioRecorder()
            let system = SignalActivitySystem(suspend: true)
            let service = RecordingService(recorder: recorder, store: store, files: files,
                activity: LiveActivityAdapter(system: system))
            let session = try await service.start(source: .iphone)
            let events = await service.events()
            await recorder.emit(.signal(RecordingSignal(peakPowerDBFS: -12, tone: 0.75)))
            await system.waitForMeasurement()
            let finalized = expectation(description: "finalization is independent of activity publication")
            let completion = Task {
                for await event in events {
                    if case .finalized(let note) = event {
                        XCTAssertEqual(note?.id, session.noteID)
                        XCTAssertEqual(note?.captureOutcome, interrupted ? .interrupted : .completed)
                        finalized.fulfill()
                        break
                    }
                }
            }
            let stopping = Task { if !interrupted { _ = try await service.stop() } }
            if interrupted { await recorder.emit(.interruption) }
            await fulfillment(of: [finalized], timeout: 1)
            await system.resumeUpdates()
            _ = try await stopping.value
            await completion.value
            let active = await service.snapshot()
            XCTAssertNil(active)
        }
    }

    func testRecordingOwnsOneActivityUntilStop() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteWhimStore.open(at: root.appendingPathComponent("whim.sqlite"))
        let files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        let activity = FixtureRecordingActivity()
        let service = RecordingService(recorder: FixtureAudioRecorder(), store: store, files: files, activity: activity)
        let first = try await service.start(source: .iphone)
        let second = try await service.start(source: .iphone)
        let started = await activity.started
        XCTAssertEqual(first, second)
        XCTAssertEqual(started, [first])
        _ = try await service.stop()
        _ = try await service.stop()
        let ended = await activity.ended
        XCTAssertEqual(ended, [first.sessionID])
    }

    func testActivityEndsOnDiscardAndSilentFinalization() async throws {
        for discard in [true, false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try SQLiteWhimStore.open(at: root.appendingPathComponent("whim.sqlite"))
            let files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
            let activity = FixtureRecordingActivity()
            let recorder = FixtureAudioRecorder()
            await recorder.setPeakPower(-100)
            let service = RecordingService(recorder: recorder, store: store, files: files, activity: activity)
            let snapshot = try await service.start(source: .iphone)
            if discard { try await service.discard() } else { _ = try await service.stop() }
            let ended = await activity.ended
            let active = await service.snapshot()
            let notes = try await store.listNotes(filter: .all)
            XCTAssertEqual(ended, [snapshot.sessionID])
            XCTAssertNil(active)
            XCTAssertTrue(notes.isEmpty)
        }
    }

    func testActivityAndRecordingFailuresLeaveNoActiveActivity() async throws {
        for failure in ["activity", "microphone", "encoder"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try SQLiteWhimStore.open(at: root.appendingPathComponent("whim.sqlite"))
            let files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
            let activity = FixtureRecordingActivity(fails: failure == "activity")
            let recorder = FixtureAudioRecorder(failure: failure)
            let service = RecordingService(recorder: recorder, store: store, files: files, activity: activity)
            do {
                _ = try await service.start(source: .iphone)
                _ = try await service.stop()
                XCTFail("Expected injected failure")
            } catch {}
            let started = await activity.started
            let ended = await activity.ended
            let active = await service.snapshot()
            let attempts = await recorder.startCount
            XCTAssertEqual(ended, started.map(\.sessionID))
            XCTAssertNil(active)
            if failure == "activity" { XCTAssertEqual(attempts, 0) }
            let sessions = try await store.recordingSessions()
            XCTAssertEqual(sessions.count, failure == "encoder" ? 1 : 0,
                "An encoder failure remains recoverable; failed activation creates no remnant")
        }
    }

    // Break: finalization trusts an adapter estimate instead of persisting the real durable file duration.
    func testFixtureAudioFinalizesAcrossRealFilesAndSQLite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("whim.sqlite")
        let store = try SQLiteWhimStore.open(at: databaseURL)
        let files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        let recorder = FixtureAudioRecorder()
        let service = RecordingService(recorder: recorder, store: store, files: files,
            timestampTitle: { _ in "Sep 4, 2026 at 10:30" })
        let snapshot = try await service.start(source: .iphone)
        await recorder.setReportedDuration(99)

        let stopped = try await service.stop()
        let finalized = try XCTUnwrap(stopped)
        let reopened: any WhimStore = try SQLiteWhimStore.open(at: databaseURL)
        let loaded = try await reopened.note(id: snapshot.noteID)
        let persisted = try XCTUnwrap(loaded)
        let sessions = try await reopened.recordingSessions()

        XCTAssertEqual(finalized.duration, 0.1, accuracy: 0.01)
        XCTAssertEqual(persisted.duration, 0.1, accuracy: 0.01)
        XCTAssertEqual(persisted.title, "Sep 4, 2026 at 10:30")
        XCTAssertGreaterThan(try AVAudioFile(forReading: persisted.audioURL).length, 0)
        XCTAssertTrue(sessions.isEmpty)
    }
}

private actor FixtureAudioRecorder: AudioRecorder {
    private let stream: AsyncStream<RecordingEvent>
    private let continuation: AsyncStream<RecordingEvent>.Continuation
    private var duration: TimeInterval = 0.1
    private var peakPower: Float = -30

    private let failure: String?
    var startCount = 0
    init(failure: String? = nil) { self.failure = failure; (stream, continuation) = AsyncStream.makeStream(of: RecordingEvent.self) }

    func events() -> AsyncStream<RecordingEvent> { stream }
    func start(at url: URL) async throws {
        startCount += 1
        if failure == "microphone" { throw RecordingServiceError.encoderFailed }
        try writeAudioFixture(to: url)
    }
    func stop() async throws {
        if failure == "encoder" { continuation.yield(.failure); return }
        continuation.yield(.encoderCompleted(duration: duration, peakPowerDBFS: peakPower))
    }
    func discard() async {}
    func emit(_ event: RecordingEvent) { continuation.yield(event) }
    func setPeakPower(_ value: Float) { peakPower = value }
    func setReportedDuration(_ duration: TimeInterval) { self.duration = duration }
}

private actor FixtureRecordingActivity: RecordingActivityManaging {
    var started: [RecordingSnapshot] = []
    var ended: [RecordingSessionID] = []
    private let fails: Bool
    init(fails: Bool = false) { self.fails = fails }
    func start(_ recording: RecordingSnapshot) async throws {
        started.append(recording)
        if fails { throw RecordingServiceError.encoderFailed }
    }
    func update(sessionID: RecordingSessionID, signal: RecordingSignal) {}
    func end(sessionID: RecordingSessionID) async { ended.append(sessionID) }
}

private actor SignalActivitySystem: RecordingActivitySystem {
    var active: [RecordingSessionID] = []
    var measurements: [RecordingSignal] = []
    var updatedSessions: [RecordingSessionID] = []
    private var suspended: Bool
    private var updateWaiter: CheckedContinuation<Void, Never>?
    private var measurementWaiter: CheckedContinuation<Void, Never>?
    init(suspend: Bool = false) { suspended = suspend }
    func waitForMeasurement() async {
        guard measurements.isEmpty else { return }
        await withCheckedContinuation { measurementWaiter = $0 }
    }
    func resumeUpdates() {
        suspended = false
        updateWaiter?.resume()
        updateWaiter = nil
    }
    func sessions() -> [RecordingSessionID] { active }
    func request(_ recording: RecordingSnapshot) { active.append(recording.sessionID) }
    func update(sessionID: RecordingSessionID, signal: RecordingSignal) async {
        measurements.append(signal)
        updatedSessions.append(sessionID)
        measurementWaiter?.resume()
        measurementWaiter = nil
        if suspended { await withCheckedContinuation { updateWaiter = $0 } }
    }
    func end(_ sessionID: RecordingSessionID) { active.removeAll { $0 == sessionID } }
}
