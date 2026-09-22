import AppIntents
import WhimCore
import XCTest

@MainActor final class StopWhimRecordingIntentTests: XCTestCase {
    func testStopFromSeparateIntentFinalizesTheAppsRecordingOnce() async throws {
        let fixture = try WhimFacadeHarness()
        defer { fixture.remove() }
        let permissions = MutablePermissions()
        await permissions.grant()
        let client = fixture.makeService(permissions: permissions)
        let runtime = WhimRuntime(make: { client })
        _ = try await client.startRecording(source: .iphone)
        _ = try await StopWhimRecordingIntent(runtime: runtime).perform()
        _ = try await StopWhimRecordingIntent(runtime: runtime).perform()
        let notes = try await client.listNotes(filter: .all)
        let active = try await client.activeRecording()
        XCTAssertEqual(notes.count, 1)
        XCTAssertNil(active)
    }
}
