import Foundation
import XCTest
@testable import WhimCore

final class NoteTests: XCTestCase {
    func testExternallyStableRawValues() {
        XCTAssertEqual(CaptureSource.iphone.rawValue, "iphone")
        XCTAssertEqual(CaptureSource.appleWatch.rawValue, "apple_watch")
        XCTAssertEqual(TitleSource.transcription.rawValue, "transcription")
        XCTAssertEqual(TitleSource.timestamp.rawValue, "timestamp")
        XCTAssertEqual(TitleSource.recovered.rawValue, "recovered")
        XCTAssertEqual(CaptureOutcome.completed.rawValue, "completed")
        XCTAssertEqual(CaptureOutcome.interrupted.rawValue, "interrupted")
        XCTAssertEqual(CaptureOutcome.recovered.rawValue, "recovered")
        XCTAssertEqual(NoteFilter.all.rawValue, "all")
        XCTAssertEqual(NoteFilter.queued.rawValue, "queued")
        XCTAssertEqual(NoteFilter.failed.rawValue, "failed")
        XCTAssertEqual(NoteFilter.sent.rawValue, "sent")
    }

    func testUUIDIdentifiersRoundTripThroughCodable() throws {
        try assertRoundTrip(NoteID())
        try assertRoundTrip(RecordingSessionID())
        try assertRoundTrip(AttemptID())
        try assertRoundTrip(ConfigurationRevisionID())
    }

    func testSentNotesMoveToSettledOnlyAfterAWeekAndKeepNewestFirstOrder() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let day: TimeInterval = 24 * 60 * 60
        let queued = projection(createdAt: now)
        let recent = projection(createdAt: now.addingTimeInterval(-9 * day), receivedAt: now.addingTimeInterval(-6 * day))
        let boundary = projection(createdAt: now.addingTimeInterval(-10 * day), receivedAt: now.addingTimeInterval(-7 * day))
        let old = projection(createdAt: now.addingTimeInterval(-30 * day), receivedAt: now.addingTimeInterval(-29 * day))

        let sections = NoteSections([queued, recent, boundary, old], now: now)

        XCTAssertEqual(recent.settledAt, now.addingTimeInterval(-6 * day))
        XCTAssertNil(queued.settledAt)
        XCTAssertEqual(sections.active.map(\.id), [queued.id, recent.id])
        XCTAssertEqual(sections.settled.map(\.id), [boundary.id, old.id])
    }

    func testSettledAtRoundTripsAndDecodesWhenAbsent() throws {
        let sent = projection(createdAt: Date(timeIntervalSince1970: 0), receivedAt: Date(timeIntervalSince1970: 60))
        let encoded = try JSONEncoder().encode(sent)
        XCTAssertEqual(try JSONDecoder().decode(NoteProjection.self, from: encoded), sent)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["settledAt"] = nil
        let legacy = try JSONDecoder().decode(NoteProjection.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.settledAt)
    }

    private func projection(createdAt: Date, receivedAt: Date? = nil) -> NoteProjection {
        let id = NoteID()
        let receipt = receivedAt.map { Receipt(attemptID: AttemptID(), noteID: id, receivedAt: $0, statusCode: 204) }
        return NoteProjection(note: Note(id: id, recordingSessionID: RecordingSessionID(), title: "Note",
            titleSource: .timestamp, createdAt: createdAt, duration: 1, source: .iphone,
            captureOutcome: .completed, requiresReview: false, audioURL: URL(fileURLWithPath: "/tmp/note.m4a"),
            delivery: Delivery(hasUsableConfiguration: true, receipt: receipt)))
    }

    private func assertRoundTrip<Value: Codable & Equatable>(_ value: Value) throws {
        let encoded = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(Value.self, from: encoded), value)
    }
}
