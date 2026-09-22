import AppIntents
import WhimCore
import XCTest

@MainActor final class RecordWhimIntentTests: XCTestCase {
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
    func end(sessionID: RecordingSessionID) async {}
}
