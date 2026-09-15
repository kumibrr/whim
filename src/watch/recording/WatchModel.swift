import Foundation
import Observation
import WhimCore
import WatchKit

@MainActor @Observable
final class WatchModel {
    let client: any WhimClient
    private let haptic: (WKHapticType) -> Void
    private var activated = false
    private var activating = false
    @ObservationIgnored nonisolated(unsafe) private var eventTask: Task<Void, Never>?
    private(set) var recording: RecordingProjection?
    private(set) var notes: [NoteProjection] = []
    private(set) var permission: PermissionStatus = .notDetermined
    private(set) var configurationAvailable = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var warned = false
    private(set) var playback: PlaybackProjection?
    var error: String?
    var showsRecent = false
    var busy = false

    init(client: any WhimClient, haptic: @escaping (WKHapticType) -> Void = { WKInterfaceDevice.current().play($0) }) {
        self.client = client; self.haptic = haptic
    }
    deinit { eventTask?.cancel() }

    /// Scene reactivation restores state. It cannot distinguish wrist-down from an icon tap,
    /// so only first launch or an explicit Record command may begin a new capture.
    func activate() async {
        guard !activating else { return }
        activating = true
        defer { activating = false }
        observeIfNeeded()
        await perform {
            let settings = try await self.client.settings()
            self.permission = settings.permissions.microphone
            self.configurationAvailable = settings.webhook != nil
            self.recording = try await self.client.activeRecording()
            if self.recording != nil { self.showsRecent = false }
            if !self.activated, self.recording == nil, self.permission == .granted {
                try await self.beginCapture()
            }
            self.activated = true
            try await self.refreshNotes()
        }
    }
    func requestPermission() async {
        await perform {
            self.permission = try await self.client.requestPermission(.microphone)
            if self.permission == .granted { try await self.beginCapture() }
        }
    }
    func record() async { await perform { try await self.beginCapture() } }
    private func beginCapture() async throws {
        let existing = try await client.activeRecording()
        recording = try await client.startRecording(source: .appleWatch)
        showsRecent = false
        if existing == nil { elapsed = 0; warned = false; haptic(.start) }
    }
    func stop() async {
        await perform {
            _ = try await self.client.stopRecording()
            self.recording = nil
            self.haptic(.stop)
            try await self.refreshNotes()
        }
    }
    func discard() async {
        await perform {
            try await self.client.discardRecording()
            self.recording = nil
            self.haptic(.stop)
        }
    }
    func retry(_ note: NoteProjection) async {
        await perform {
            if note.requiresReview { try await self.client.sendRecovered(noteID: note.id) }
            else { try await self.client.retry(noteID: note.id) }
            try await self.refreshNotes()
        }
    }
    func delete(_ note: NoteProjection) async {
        await perform { try await self.client.delete(noteID: note.id); try await self.refreshNotes() }
    }
    func play(_ note: NoteProjection) async {
        await perform { self.playback = try await self.client.playNote(note.id) }
    }
    func stopPlayback() async { await client.stopPlayback(); playback = nil }
    func refreshPlayback() async { playback = await client.playbackSnapshot() }
    private func refreshNotes() async throws { notes = try await client.listNotes(filter: .all) }
    private func perform(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await operation(); error = nil }
        catch { self.error = String(describing: error) }
    }
    private func observeIfNeeded() {
        guard eventTask == nil else { return }
        let stream = client.events()
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event.type {
                case .recordingStarted: self.recording = event.recording
                case .recordingStopped, .recordingDiscarded: self.recording = nil
                case .recordingProgress: if let elapsed = event.elapsedSeconds { self.elapsed = elapsed }
                case .recordingMaximumDurationWarning: self.warned = true; self.haptic(.notification)
                case .noteChanged, .noteDeleted, .notesReset: try? await self.refreshNotes()
                default: break
                }
            }
        }
    }
}
