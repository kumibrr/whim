import AVFoundation
import Foundation
import XCTest
@testable import WhimCore

final class RecordingServiceIntegrationTests: XCTestCase {
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
    func end(sessionID: RecordingSessionID) async { ended.append(sessionID) }
}
