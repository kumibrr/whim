import AppIntents
import WhimCore
import XCTest

@MainActor final class RecordWhimIntentTests: XCTestCase {
    // Break: a second iPhone shortcut invocation only focuses capture instead of saving and delivering it.
    func testSecondInvocationStopsAndSendsThenNextInvocationStartsANewSession() async throws {
        let fixture = try WhimFacadeHarness()
        defer { fixture.remove() }
        _ = try await fixture.configuration.save(.init(endpoint: "https://example.com/whim"))
        let permissions = MutablePermissions()
        await permissions.grant()
        let client = fixture.makeService(permissions: permissions)
        let intent = RecordWhimIntent(runtime: WhimRuntime(make: { client }))

        _ = try await intent.perform()
        let first = try await client.activeRecording()
        XCTAssertNotNil(first)
        _ = try await intent.perform()
        let active = try await client.activeRecording()
        XCTAssertNil(active)
        let notes = try await client.listNotes(filter: .all)
        guard let note = notes.first else { return XCTFail("The second invocation must save a Note") }
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(note.hasLocalAudio)
        for _ in 0..<200 {
            if try await client.note(id: note.id)?.status == .sent { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let delivered = try await client.note(id: note.id)
        XCTAssertEqual(delivered?.status, .sent)

        _ = try await intent.perform()
        let next = try await client.activeRecording()
        XCTAssertNotNil(next)
        XCTAssertNotEqual(first?.sessionID, next?.sessionID)
        try await client.discardRecording()
    }

    // Break: stopping an app-started recording while offline loses the Note or starts another capture.
    func testInvocationStopsAppRecordingAndQueuesDeliveryWhileOffline() async throws {
        let fixture = try WhimFacadeHarness()
        defer { fixture.remove() }
        _ = try await fixture.configuration.save(.init(endpoint: "https://example.com/whim"))
        let permissions = MutablePermissions()
        await permissions.grant()
        let client = fixture.makeService(isConnected: { false }, permissions: permissions)
        _ = try await client.startRecording(source: .iphone)
        _ = try await RecordWhimIntent(runtime: WhimRuntime(make: { client })).perform()
        let active = try await client.activeRecording()
        let notes = try await client.listNotes(filter: .all)
        XCTAssertNil(active)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.status, .queued)
        XCTAssertEqual(notes.first?.hasLocalAudio, true)
    }

    func testActivityFailureRequestsRecoverableForegroundAndLeavesNoCapture() async throws {
        let fixture = try WhimFacadeHarness()
        defer { fixture.remove() }
        let permissions = MutablePermissions()
        await permissions.grant()
        let client = fixture.makeService(permissions: permissions, activity: UnavailableActivity())
        let runtime = WhimRuntime(make: { client })
        do {
            _ = try await RecordWhimIntent(runtime: runtime).perform()
            XCTFail("Unavailable Live Activity must request foreground recovery")
        } catch { XCTAssertTrue(error is AppIntentError) }
        let recording = try await client.activeRecording()
        XCTAssertNil(recording)
    }
    func testMissingPermissionRequestsForegroundWithoutStartingCapture() async throws {
        let fixture = try WhimFacadeHarness()
        defer { fixture.remove() }
        let client = fixture.makeService(permissions: DeniedFacadePermissions())
        let runtime = WhimRuntime(make: { client })
        do {
            _ = try await RecordWhimIntent(runtime: runtime).perform()
            XCTFail("Missing permission must request foreground continuation")
        } catch { XCTAssertTrue(error is AppIntentError) }
        let recording = try await client.activeRecording()
        XCTAssertNil(recording)
    }
}

private struct UnavailableActivity: RecordingActivityManaging {
    func start(_ recording: RecordingSnapshot) async throws { throw CocoaError(.featureUnsupported) }
    func update(sessionID: RecordingSessionID, signal: RecordingSignal) async {}
    func end(sessionID: RecordingSessionID) async {}
}
