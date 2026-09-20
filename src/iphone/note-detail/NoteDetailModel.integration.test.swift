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

@MainActor final class NoteDetailCardIntegrationTests: XCTestCase {
    func testCardLoadsWaveformOnceAndReflectsPlayback() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let waveform = DetailWaveform()
        let client = harness.makeService(playback: FacadePlayback(), permissions: GrantedPermissions(), waveform: waveform)
        _ = try await client.startRecording(source: .iphone)
        let saved = try await client.stopRecording()
        let id = try XCTUnwrap(saved).id
        let model = NoteDetailModel(client: client, noteID: id)
        await model.refresh()
        await model.loadWaveform()
        await model.loadWaveform()
        XCTAssertEqual(model.waveform, .samples([0.25, 0.75]))
        let loads = await waveform.loads
        XCTAssertEqual(loads, 1)
        await model.play()
        XCTAssertEqual(model.playback?.noteID, id.rawValue.uuidString.lowercased())
        XCTAssertEqual(model.playback?.durationSeconds, 2)
        await model.stopPlayback()
        XCTAssertNil(model.playback)
        try harness.files.delete(noteID: id)
        await model.refresh()
        XCTAssertNil(model.waveform)
        XCTAssertNil(model.playback)
    }

    func testDelayedWaveformCannotRestoreDeletedAudio() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let waveform = GatedWaveform()
        let client = harness.makeService(permissions: GrantedPermissions(), waveform: waveform)
        _ = try await client.startRecording(source: .iphone)
        let saved = try await client.stopRecording()
        let id = try XCTUnwrap(saved).id
        let model = NoteDetailModel(client: client, noteID: id)
        await model.refresh()
        let loading = Task { await model.loadWaveform() }
        await waveform.waitUntilStarted()
        try await client.delete(noteID: id)
        await model.refresh()
        await waveform.release()
        await loading.value
        XCTAssertNil(model.note)
        XCTAssertNil(model.waveform)
    }
}

private actor DetailWaveform: AudioWaveformAdapter {
    private(set) var loads = 0
    func waveform(at url: URL) -> [Float] { loads += 1; return [0.25, 0.75] }
}
