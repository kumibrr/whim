import AppIntents
import UIKit
import WhimCore
import XCTest

@MainActor final class RecordWhimControlTests: XCTestCase {
    // Break: the Lock Screen control does not share the shortcut's stop-and-send behavior.
    func testControlStartsThenStopsAndSavesWithoutRequiringUnlock() async throws {
        let fixture = try WhimFacadeHarness()
        defer { fixture.remove() }
        let permissions = MutablePermissions()
        await permissions.grant()
        let client = fixture.makeService(permissions: permissions)
        let runtime = WhimRuntime(make: { client })
        let control = RecordWhimControl(action: RecordWhimIntent(runtime: runtime))
        _ = try await control.action.perform()
        let first = try await client.activeRecording()
        _ = try await control.action.perform()
        let second = try await client.activeRecording()
        XCTAssertNotNil(first)
        XCTAssertNil(second)
        let notes = try await client.listNotes(filter: .all)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.status, .setupRequired)
        XCTAssertEqual(RecordWhimIntent.authenticationPolicy, .alwaysAllowed)
        XCTAssertFalse(RecordWhimIntent.openAppWhenRun)
    }

    // Break: the control shows a glyph other than the compact Whim mark, or one Control Center cannot render.
    func testControlShowsTheCompactWhimMarkSymbol() throws {
        XCTAssertEqual(RecordWhimControl.symbolName, "whim.small.symbol")
        let image = try XCTUnwrap(UIImage(named: RecordWhimControl.symbolName, in: Bundle(for: Self.self), with: nil))
        XCTAssertTrue(image.isSymbolImage, "Controls only render symbols, so the compact mark must ship as a custom symbol")
    }
}
