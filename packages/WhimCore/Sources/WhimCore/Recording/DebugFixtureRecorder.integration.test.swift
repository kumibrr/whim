import Foundation
import XCTest
@testable import WhimCore

final class DebugFixtureRecorderIntegrationTests: XCTestCase {
    func testLaunchFixtureFinalizesThroughRealRecordingService() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "configuration-test-fixture", withExtension: "m4a", subdirectory: "Fixtures"))
        let recorder = try XCTUnwrap(DebugFixtureRecorder.from(arguments: ["app", "-WhimFixtureAudio", fixture.path]))
        let store = try SQLiteWhimStore.open(at: root.appendingPathComponent("notes.sqlite"))
        let files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        let service = RecordingService(recorder: recorder, store: store, files: files)
        _ = try await service.start(source: .iphone)
        let note = try await service.stop()
        XCTAssertNotNil(note)
        let notes = try await store.listNotes(filter: .all)
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].hasLocalAudio)
        XCTAssertGreaterThan(notes[0].duration, 0)
    }
}
