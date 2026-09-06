import AVFoundation
import Foundation
import XCTest
@testable import WhimCore

final class RecordingServiceIntegrationTests: XCTestCase {
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

    init() { (stream, continuation) = AsyncStream.makeStream(of: RecordingEvent.self) }

    func events() -> AsyncStream<RecordingEvent> { stream }
    func start(at url: URL) async throws { try writeAudioFixture(to: url) }
    func stop() async throws {
        continuation.yield(.encoderCompleted(duration: duration, peakPowerDBFS: -30))
    }
    func discard() async {}
    func setReportedDuration(_ duration: TimeInterval) { self.duration = duration }
}
