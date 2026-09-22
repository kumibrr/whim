import Foundation
import XCTest
@testable import WhimCore

final class ComplicationSnapshotTests: XCTestCase {
    // Break: a killed Watch app leaves a recording timer on the face indefinitely.
    func testRecordingExpiresAtMaximumDurationWithoutLosingAttention() {
        let start = Date(timeIntervalSince1970: 100)
        let recording = RecordingProjection(sessionID: "session", noteID: "note", source: .appleWatch, createdAt: start)
        let snapshot = ComplicationSnapshot(recording: recording, hasFailedNotes: true)
        XCTAssertEqual(snapshot.activeRecording(at: start.addingTimeInterval(299)), recording)
        XCTAssertNil(snapshot.activeRecording(at: start.addingTimeInterval(300)))
        XCTAssertTrue(snapshot.hasFailedNotes)
    }
    func testSharedSnapshotPreservesSessionTimestampAndAttention() throws {
        let snapshot = ComplicationSnapshot(recording: RecordingProjection(sessionID: "session", noteID: "note", source: .appleWatch, createdAt: Date(timeIntervalSince1970: 100)), hasFailedNotes: true)
        let restored = try JSONDecoder().decode(ComplicationSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored, snapshot)
    }
}
