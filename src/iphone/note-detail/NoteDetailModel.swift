import Foundation
import Observation
import WhimCore

@MainActor @Observable public final class NoteDetailModel {
    public private(set) var note: NoteDetailProjection?
    public private(set) var waveform: AudioWaveform?
    public private(set) var playback: PlaybackProjection?
    public private(set) var isPlaying = false
    public private(set) var isPending = false
    public private(set) var error: IPhoneError?
    public private(set) var deleted = false
    private let client: any WhimClient
    private let noteID: NoteID
    private var generation = 0
    private var loadingWaveform = false
    private var audioGeneration = 0
    public init(client: any WhimClient, noteID: NoteID) { self.client = client; self.noteID = noteID }
    public func refresh() async {
        generation += 1
        let token = generation
        do {
            let value = try await client.note(id: noteID)
            let playback = await client.playbackSnapshot()
            guard token == generation, !Task.isCancelled else { return }
            if value?.hasLocalAudio != true {
                waveform = nil
                audioGeneration += 1
            }
            note = value
            self.playback = value?.hasLocalAudio == true && playback?.noteID == noteID.rawValue.uuidString.lowercased() ? playback : nil
            isPlaying = value?.hasLocalAudio == true && playback?.noteID == noteID.rawValue.uuidString.lowercased() && playback?.isPlaying == true
        } catch is CancellationError {} catch { self.error = IPhoneError(error) }
    }
    public func loadWaveform() async {
        guard note?.hasLocalAudio == true, waveform == nil, !loadingWaveform else { return }
        loadingWaveform = true
        let token = audioGeneration
        defer { loadingWaveform = false }
        let value = try? await client.waveform(noteID: noteID)
        guard !Task.isCancelled, audioGeneration == token, note?.hasLocalAudio == true else { return }
        waveform = value ?? .unavailable
    }
    public func play() async { await perform { _ = try await client.playNote(noteID) } }
    public func stopPlayback() async { await client.stopPlayback(); playback = nil; isPlaying = false }
    public func retry() async { await perform { try await client.retry(noteID: noteID) } }
    public func sendRecovered() async { await perform { try await client.sendRecovered(noteID: noteID) } }
    public func delete() async { await perform { try await client.delete(noteID: noteID); deleted = true } }
    private func perform(_ operation: () async throws -> Void) async {
        guard !isPending else { return }; isPending = true; error = nil
        defer { isPending = false }
        do { try await operation(); await refresh() }
        catch is CancellationError {} catch { self.error = IPhoneError(error) }
    }
}
