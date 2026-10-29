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
    // Break: rapid microphone ticks flood ActivityKit or late samples update an ended session.
    func testMeterPublicationIsBoundedAndEndsWithTheSession() async throws {
        let session = RecordingSnapshot(sessionID: RecordingSessionID(), noteID: NoteID(), source: .iphone, createdAt: Date())
        let system = ActivitySystemFixture()
        let clock = ActivityClock()
        let adapter = LiveActivityAdapter(system: system, clock: clock)
        try await adapter.start(session)
        let soft = RecordingSignal(peakPowerDBFS: -30, tone: 0.2)
        let loud = RecordingSignal(peakPowerDBFS: -12, tone: 0.8)
        await adapter.update(sessionID: session.sessionID, signal: soft)
        clock.advance(0.1)
        await adapter.update(sessionID: session.sessionID, signal: loud)
        clock.advance(0.15)
        await adapter.update(sessionID: session.sessionID, signal: loud)
        clock.advance(0.25)
        let silence = RecordingSignal(peakPowerDBFS: -160, tone: 0)
        await adapter.update(sessionID: session.sessionID, signal: silence)
        await adapter.end(sessionID: session.sessionID)
        clock.advance(1)
        await adapter.update(sessionID: session.sessionID, signal: loud)
        await adapter.update(sessionID: RecordingSessionID(), signal: loud)
        let measurements = await system.measurements
        XCTAssertEqual(measurements, [soft, loud, silence])
        // A new Recording Session must publish immediately, independently of the previous one.
        try await adapter.start(session)
        await adapter.update(sessionID: session.sessionID, signal: soft)
        let restarted = await system.measurements
        XCTAssertEqual(restarted, [soft, loud, silence, soft])
    }

    // Break: steady voice keeps reloading the remote controls even though their content is unchanged.
    func testUnchangedVoiceDoesNotRepublishButTheNextMeasurementDoes() async throws {
        let session = RecordingSnapshot(sessionID: RecordingSessionID(), noteID: NoteID(), source: .iphone, createdAt: Date())
        let system = ActivitySystemFixture()
        let clock = ActivityClock()
        let adapter = LiveActivityAdapter(system: system, clock: clock)
        try await adapter.start(session)
        let voice = RecordingSignal(peakPowerDBFS: -12, tone: 0.5)
        await adapter.update(sessionID: session.sessionID, signal: voice)
        clock.advance(1)
        await adapter.update(sessionID: session.sessionID, signal: voice)
        clock.advance(1)
        let silence = RecordingSignal(peakPowerDBFS: -160, tone: 0)
        await adapter.update(sessionID: session.sessionID, signal: silence)
        let measurements = await system.measurements
        XCTAssertEqual(measurements, [voice, silence])
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
    private(set) var measurements: [RecordingSignal] = []
    func update(sessionID: RecordingSessionID, signal: RecordingSignal) { measurements.append(signal) }
    func end(_ sessionID: RecordingSessionID) { recordings.removeAll { $0.sessionID == sessionID } }
}

private final class ActivityClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 100)
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date += seconds } }
}
