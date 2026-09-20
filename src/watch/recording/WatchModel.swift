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
    private(set) var synchronization = WatchSettingsProjection.unavailable
    private(set) var elapsed: TimeInterval = 0
    private(set) var peakPowerDBFS = -160.0
    private(set) var warned = false
    private(set) var playback: PlaybackProjection?
    private var commandError: String?
    private var refreshError: String?
    private var commandRevision = UUID()
    private var refreshRevision = 0
    private enum NoteAction { case retry, delete }
    private var noteActions: [NoteID: (token: UUID, action: NoteAction)] = [:]
    var error: String? { commandError ?? refreshError }
    var showsRecent = false
    private(set) var captureBusy = false

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
            self.synchronization = settings.watch
            self.recording = try await self.client.activeRecording()
            if self.recording != nil { self.showsRecent = false }
            if !self.activated, self.recording == nil, self.permission == .granted {
                try await self.beginCapture()
            }
            self.activated = true
            await self.refreshNotes()
        }
    }
    func requestPermission() async {
        await performCapture {
            self.permission = try await self.client.requestPermission(.microphone)
            if self.permission == .granted { try await self.beginCapture() }
        }
    }
    func record() async { await performCapture { try await self.beginCapture() } }
    private func beginCapture() async throws {
        let existing = try await client.activeRecording()
        recording = try await client.startRecording(source: .appleWatch)
        showsRecent = false
        if existing == nil { elapsed = 0; peakPowerDBFS = -160; warned = false; haptic(.start) }
    }
    func stop() async {
        await performCapture {
            _ = try await self.client.stopRecording()
            self.recording = nil
            self.peakPowerDBFS = -160
            self.haptic(.stop)
            await self.refreshNotes()
        }
    }
    func discard() async {
        await performCapture {
            try await self.client.discardRecording()
            self.recording = nil
            self.peakPowerDBFS = -160
            self.haptic(.stop)
        }
    }
    func isActing(on id: NoteID) -> Bool { noteActions[id] != nil }
    func isDeleting(_ id: NoteID) -> Bool { noteActions[id]?.action == .delete }
    func retry(_ note: NoteProjection) async {
        guard noteActions[note.id] == nil else { return }
        let token = UUID()
        noteActions[note.id] = (token, .retry)
        defer { if noteActions[note.id]?.token == token { noteActions[note.id] = nil } }
        await perform {
            if note.requiresReview { try await self.client.sendRecovered(noteID: note.id) }
            else { try await self.client.retry(noteID: note.id) }
            await self.refreshNotes()
        }
    }
    @discardableResult
    func delete(_ note: NoteProjection) async -> Bool {
        guard !isDeleting(note.id) else { return false }
        let token = UUID()
        noteActions[note.id] = (token, .delete)
        defer { if noteActions[note.id]?.token == token { noteActions[note.id] = nil } }
        return await perform {
            try await self.client.delete(noteID: note.id)
            await self.refreshNotes()
        }
    }
    func play(_ note: NoteProjection) async {
        await perform { self.playback = try await self.client.playNote(note.id) }
    }
    func stopPlayback() async { await client.stopPlayback(); playback = nil }
    func refreshPlayback() async { playback = await client.playbackSnapshot() }
    func refreshNotes() async {
        refreshRevision += 1
        let revision = refreshRevision
        do {
            let latest = try await client.listNotes(filter: .all)
            guard revision == refreshRevision else { return }
            notes = latest
            refreshError = nil
        } catch {
            guard revision == refreshRevision else { return }
            refreshError = "Recent Notes could not be refreshed. Try again."
        }
    }
    private func performCapture(_ operation: () async throws -> Void) async {
        guard !captureBusy else { return }
        captureBusy = true
        defer { captureBusy = false }
        await perform(operation)
    }
    @discardableResult
    private func perform(_ operation: () async throws -> Void) async -> Bool {
        let revision = UUID()
        commandRevision = revision
        do {
            try await operation()
            if commandRevision == revision { commandError = nil }
            return true
        } catch is CancellationError {
            return false
        } catch {
            if commandRevision == revision {
                commandError = (error as? WhimServiceError)?.description
                    ?? "Whim could not complete this action. Try again."
            }
            return false
        }
    }
    private func observeIfNeeded() {
        guard eventTask == nil else { return }
        let stream = client.events()
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event.type {
                case .recordingStarted:
                    self.recording = event.recording
                    self.peakPowerDBFS = -160
                case .recordingStopped, .recordingDiscarded:
                    self.recording = nil
                    self.peakPowerDBFS = -160
                case .recordingProgress:
                    if let elapsed = event.elapsedSeconds { self.elapsed = elapsed }
                    if let power = event.peakPowerDBFS { self.peakPowerDBFS = Double(power) }
                case .recordingMaximumDurationWarning: self.warned = true; self.haptic(.notification)
                case .noteChanged, .noteDeleted, .notesReset: await self.refreshNotes()
                case .settingsChanged:
                    if let settings = try? await self.client.settings() {
                        self.configurationAvailable = settings.webhook != nil
                        self.synchronization = settings.watch
                    }
                default: break
                }
            }
        }
    }
}
