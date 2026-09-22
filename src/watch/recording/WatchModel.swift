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
    private(set) var captureReady = false
    private(set) var isResolvingError = false
    private var commandFailure: ActionableFailure?
    private var maintenanceFailure: ActionableFailure?
    private var maintenanceTask: Task<Void, Never>?
    private var failedPlaybackNote: NoteProjection?
    private var settingsFailure: ActionableFailure?
    private var settingsRevision = 0
    private var captureRevision = 0
    private var lastCaptureCommand = CaptureCommand.start
    private enum CaptureCommand { case start, stop, discard }
    var visibleFailure: ActionableFailure? {
        if let commandFailure, commandFailure.blocksCapture { return commandFailure }
        if captureReady, permission == .denied || permission == .restricted {
            return ActionableFailure(WhimServiceError.permissionDenied, operation: .capture)
        }
        if let commandFailure { return commandFailure }
        if refreshError != nil { return ActionableFailure(WhimServiceError.audioUnavailable, operation: .history) }
        return settingsFailure ?? maintenanceFailure
    }
    func dismissAuxiliaryError() {
        if refreshError != nil { refreshError = nil } else if settingsFailure != nil { settingsFailure = nil } else { maintenanceFailure = nil }
    }
    func retryVisibleFailure() async {
        guard !isResolvingError else { return }
        isResolvingError = true
        defer { isResolvingError = false }
        if visibleFailure?.action == .microphoneSettings { await activate(); return }
        switch visibleFailure?.operation {
        case .history: await refreshNotes()
        case .settings: await refreshSettings()
        case .request:
            commandFailure = nil; commandError = nil
            await refreshNotes()
        case .playback:
            if let note = failedPlaybackNote { await play(note) }
        case .maintenance:
            maintenanceTask = nil; startMaintenanceIfNeeded()
            await maintenanceTask?.value
        case .capture:
            switch lastCaptureCommand {
            case .start: await record()
            case .stop: await stop()
            case .discard: await discard()
            }
        default: await activate()
        }
    }
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
    func activate(captureURL: URL? = nil) async {
        guard !activating else { return }
        activating = true
        observeIfNeeded()
        let loaded = await perform(operation: .preparation) {
            let revision = self.captureRevision
            let startup = try await self.client.startup()
            self.permission = startup.microphone
            self.captureReady = true
            if revision == self.captureRevision { self.recording = startup.recording }
            if self.recording != nil { self.showsRecent = false }
            if captureURL == nil, !self.activated, self.recording == nil, self.permission == .granted, !self.captureBusy {
                self.captureBusy = true
                defer { self.captureBusy = false }
                self.lastCaptureCommand = .start
                try await self.beginCapture()
            }
            self.activated = true
        }
        activating = false
        if loaded {
            if let captureURL { await handleCaptureURL(captureURL) }
            startMaintenanceIfNeeded()
            async let settings: Void = refreshSettings()
            async let notes: Void = refreshNotes()
            _ = await (settings, notes)
        }
    }
    private func startMaintenanceIfNeeded() {
        guard maintenanceTask == nil else { return }
        maintenanceTask = Task { [weak self, client] in
            do {
                try await client.maintain()
                guard let self, !Task.isCancelled else { return }
                self.maintenanceFailure = nil
                await self.refreshNotes()
            } catch is CancellationError {
                guard let self, !Task.isCancelled else { return }
                self.maintenanceTask = nil
                self.startMaintenanceIfNeeded()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.maintenanceFailure = ActionableFailure(error, operation: .maintenance)
                await self.refreshNotes()
            }
        }
    }
    private func refreshSettings() async {
        settingsRevision += 1
        let revision = settingsRevision
        do {
            let settings = try await client.settings()
            guard revision == settingsRevision else { return }
            configurationAvailable = settings.webhook != nil
            synchronization = settings.watch
            settingsFailure = nil
        } catch { if revision == settingsRevision { settingsFailure = ActionableFailure(error, operation: .settings) } }
    }
    func requestPermission() async {
        await performCapture {
            self.permission = try await self.client.requestPermission(.microphone)
            if self.permission == .granted { try await self.beginCapture() }
        }
    }
    func handleCaptureURL(_ url: URL) async {
        guard url.scheme == "whim", url.host == "record" else { return }
        await record()
    }
    func record() async {
        lastCaptureCommand = .start
        await performCapture { try await self.beginCapture() }
    }
    private func beginCapture() async throws {
        let existing = try await client.activeRecording()
        recording = try await client.startRecording(source: .appleWatch)
        showsRecent = false
        if existing == nil { elapsed = 0; peakPowerDBFS = -160; warned = false; haptic(.start) }
    }
    func stop() async {
        lastCaptureCommand = .stop
        await performCapture {
            _ = try await self.client.stopRecording()
            self.recording = nil
            self.peakPowerDBFS = -160
            self.haptic(.stop)
            Task { await self.refreshNotes() }
        }
    }
    func discard() async {
        lastCaptureCommand = .discard
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
        failedPlaybackNote = note
        if await perform(operation: .playback, { self.playback = try await self.client.playNote(note.id) }) { failedPlaybackNote = nil }
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
        await perform(operation: .capture, operation)
    }
    @discardableResult
    private func perform(operation context: ActionableFailure.Operation = .request, _ operation: () async throws -> Void) async -> Bool {
        let revision = UUID()
        commandRevision = revision
        do {
            try await operation()
            if commandRevision == revision { commandError = nil; commandFailure = nil }
            return true
        } catch is CancellationError {
            return false
        } catch {
            if commandRevision == revision {
                commandFailure = ActionableFailure(error, operation: context)
                commandError = commandFailure?.message
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
                    self.showsRecent = false
                    self.captureRevision += 1
                    self.recording = event.recording
                    self.peakPowerDBFS = -160
                case .recordingStopped, .recordingDiscarded:
                    self.captureRevision += 1
                    self.recording = nil
                    self.peakPowerDBFS = -160
                case .recordingProgress:
                    if let elapsed = event.elapsedSeconds { self.elapsed = elapsed }
                    if let power = event.peakPowerDBFS { self.peakPowerDBFS = Double(power) }
                case .recordingMaximumDurationWarning: self.warned = true; self.haptic(.notification)
                case .noteChanged, .noteDeleted: Task { await self.refreshNotes() }
                case .notesReset:
                    self.captureRevision += 1
                    self.recording = nil; self.notes = []
                    Task { await self.refreshNotes(); await self.refreshSettings() }
                case .settingsChanged:
                    Task { await self.refreshSettings() }
                default: break
                }
            }
        }
    }
}
