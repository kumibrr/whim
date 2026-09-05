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

    private func assertRoundTrip<Value: Codable & Equatable>(_ value: Value) throws {
        let encoded = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(Value.self, from: encoded), value)
    }
}
