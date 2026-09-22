import Foundation
import XCTest
@testable import WhimCore

final class LiveActivityAdapterTests: XCTestCase {
    // Break: process re-entry creates duplicate activities or leaves a dead recording visible.
    func testReentryReusesSessionIdentityAndRemovesOrphans() async throws {
        let session = RecordingSnapshot(sessionID: RecordingSessionID(), noteID: NoteID(), source: .iphone, createdAt: Date(timeIntervalSince1970: 500))
        let system = ActivitySystemFixture()
        try await LiveActivityAdapter(system: system).start(session)
        try await LiveActivityAdapter(system: system).start(session)
        let active = await system.recordings
        XCTAssertEqual(active, [session])
        await LiveActivityAdapter(system: system).reconcile(activeSessionID: nil)
        let remaining = await system.recordings
        XCTAssertTrue(remaining.isEmpty)
    }
    func testEndDoesNotEndADifferentSession() async throws {
        let session = RecordingSnapshot(sessionID: RecordingSessionID(), noteID: NoteID(), source: .iphone, createdAt: Date())
        let system = ActivitySystemFixture()
        let adapter = LiveActivityAdapter(system: system)
        try await adapter.start(session)
        await adapter.end(sessionID: RecordingSessionID())
        let active = await system.recordings
        XCTAssertEqual(active, [session])
        await adapter.end(sessionID: session.sessionID)
        await adapter.end(sessionID: session.sessionID)
        let remaining = await system.recordings
        XCTAssertTrue(remaining.isEmpty)
    }
}
private actor ActivitySystemFixture: RecordingActivitySystem {
    private(set) var recordings: [RecordingSnapshot] = []
    func sessions() -> [RecordingSessionID] { recordings.map(\.sessionID) }
    func request(_ recording: RecordingSnapshot) { recordings.append(recording) }
    func end(_ sessionID: RecordingSessionID) { recordings.removeAll { $0.sessionID == sessionID } }
}
