import Foundation
import XCTest
@testable import WhimCore

final class PlaybackAdapterTests: XCTestCase {
    func testStoppingPlaybackReleasesSessionAndNotifiesOtherAudioOnce() async throws {
        let session = PlaybackSessionSpy()
        let hardware = PlaybackHardwareStub()
        let adapter: any PlaybackAdapter = SystemPlaybackAdapter(audioSession: session.boundary, makePlayer: { _ in hardware })
        _ = try await adapter.play(noteID: NoteID(), url: URL(fileURLWithPath: "/note.m4a"))
        await adapter.stop()
        await adapter.stop()
        XCTAssertEqual(session.notifications, [true])
        let snapshot = await adapter.snapshot()
        XCTAssertNil(snapshot)
    }

    func testCompletionReleasesSessionWithoutPollingOrStopping() async throws {
        let session = PlaybackSessionSpy()
        let hardware = PlaybackHardwareStub()
        let adapter: any PlaybackAdapter = SystemPlaybackAdapter(audioSession: session.boundary, makePlayer: { _ in hardware })
        _ = try await adapter.play(noteID: NoteID(), url: URL(fileURLWithPath: "/note.m4a"))
        await hardware.finish()
        XCTAssertEqual(session.notifications, [true])
        let snapshot = await adapter.snapshot()
        XCTAssertNil(snapshot)
    }

    func testLateCompletionFromReplacedPlaybackCannotReleaseCurrentSession() async throws {
        let session = PlaybackSessionSpy()
        let first = PlaybackHardwareStub()
        let second = PlaybackHardwareStub()
        let adapter: any PlaybackAdapter = SystemPlaybackAdapter(audioSession: session.boundary,
            makePlayer: { $0.lastPathComponent == "first.m4a" ? first : second })
        _ = try await adapter.play(noteID: NoteID(), url: URL(fileURLWithPath: "/first.m4a"))
        let secondID = NoteID()
        _ = try await adapter.play(noteID: secondID, url: URL(fileURLWithPath: "/second.m4a"))
        await first.finish()
        XCTAssertEqual(session.notifications, [true])
        let current = await adapter.snapshot()
        XCTAssertEqual(current?.noteID, secondID.rawValue.uuidString.lowercased())
        await second.finish()
        XCTAssertEqual(session.notifications, [true, true])
    }

    func testFailedPreparationStartAndConstructionReleaseSession() async throws {
        for failure in 0...2 {
            let session = PlaybackSessionSpy()
            let hardware = PlaybackHardwareStub(prepare: failure != 0, play: failure != 1)
            let adapter: any PlaybackAdapter = SystemPlaybackAdapter(audioSession: session.boundary, makePlayer: { _ in
                if failure == 2 { throw WhimServiceError.audioUnavailable }
                return hardware
            })
            do {
                _ = try await adapter.play(noteID: NoteID(), url: URL(fileURLWithPath: "/note.m4a"))
                XCTFail("Expected playback to fail")
            } catch {}
            XCTAssertEqual(session.notifications, [true], "Failure \(failure)")
            let snapshot = await adapter.snapshot()
            XCTAssertNil(snapshot)
        }
    }
}

private final class PlaybackSessionSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []
    var notifications: [Bool] { lock.withLock { values } }
    var boundary: PlaybackAudioSession {
        .init(activate: {}, deactivate: { [self] notifyOthers in lock.withLock { values.append(notifyOthers) } })
    }
}
private final class PlaybackHardwareStub: PlaybackHardware, @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable () async -> Void)?
    private let prepared: Bool
    private let started: Bool
    init(prepare: Bool = true, play: Bool = true) { prepared = prepare; started = play }
    var isPlaying: Bool { true }
    var currentTime: TimeInterval { 0 }
    var duration: TimeInterval { 1 }
    func prepareToPlay() -> Bool { prepared }
    func play() -> Bool { started }
    func stop() {}
    func onCompletion(_ handler: @escaping @Sendable () async -> Void) { lock.withLock { completion = handler } }
    func finish() async { await lock.withLock { completion }?() }
}
