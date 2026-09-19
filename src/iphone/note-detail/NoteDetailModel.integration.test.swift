import XCTest
import WhimCore
@testable import WhimIPhone

@MainActor final class NoteDetailModelIntegrationTests: XCTestCase {
    func testPlaybackAndDeletionUseCanonicalNote() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService(playback: FacadePlayback(), permissions: GrantedPermissions())
        _ = try await client.startRecording(source: .iphone)
        let saved = try await client.stopRecording()
        let note = try XCTUnwrap(saved)
        let model = NoteDetailModel(client: client, noteID: note.id)
        await model.refresh()
        XCTAssertEqual(model.note?.id, note.id.rawValue.uuidString.lowercased())
        await model.play()
        XCTAssertTrue(model.isPlaying)
        try await client.delete(noteID: note.id)
        await model.refresh()
        XCTAssertNil(model.note)
        XCTAssertFalse(model.isPlaying)
    }
    func testDelayedDetailLookupCannotRestoreDeletedNote() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let playback = GatedPlayback()
        let client = harness.makeService(playback: playback, permissions: GrantedPermissions())
        _ = try await client.startRecording(source: .iphone)
        let saved = try await client.stopRecording()
        let id = try XCTUnwrap(saved).id
        let model = NoteDetailModel(client: client, noteID: id)
        await playback.arm()
        let old = Task { await model.refresh() }
        await playback.waitForSnapshot(1)
        try await client.delete(noteID: id)
        await model.refresh()
        await playback.release(1)
        await old.value
        XCTAssertNil(model.note)
        XCTAssertFalse(model.isPlaying)
    }
    func testMissingAudioRemovesPlaybackAvailability() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService(playback: FacadePlayback(), permissions: GrantedPermissions())
        _ = try await client.startRecording(source: .iphone)
        let saved = try await client.stopRecording()
        let id = try XCTUnwrap(saved).id
        let model = NoteDetailModel(client: client, noteID: id)
        await model.refresh(); await model.play()
        try harness.files.delete(noteID: id)
        await model.refresh()
        XCTAssertEqual(model.note?.hasLocalAudio, false)
        XCTAssertFalse(model.isPlaying)
    }

}
