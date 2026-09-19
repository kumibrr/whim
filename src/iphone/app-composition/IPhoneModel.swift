import Foundation
import Observation
import WhimCore

@MainActor @Observable public final class IPhoneModel {
    public let client: any WhimClient
    public private(set) var settings: SettingsProjection?
    public private(set) var recording: RecordingProjection?
    public private(set) var notes: [NoteProjection] = []
    public private(set) var playback: PlaybackProjection?
    public private(set) var error: IPhoneError?
    public private(set) var isRefreshing = false
    public private(set) var isPending = false
    public private(set) var isRecordingPending = false
    public private(set) var elapsedSeconds = 0.0
    public private(set) var peakPowerDBFS = -160.0
    public private(set) var feedback = ""
    public private(set) var offersContextualPermissions = false
    public private(set) var revision = 0
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var lastSequence: UInt64 = 0
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var eventsDuringRefresh: [WhimEvent] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshRequested = false
    @ObservationIgnored private var completionGeneration = 0

    public init(client: any WhimClient) { self.client = client }
    deinit { observation?.cancel() }
    public func start() async {
        guard observation == nil else { return }
        lastSequence = 0
        let stream = client.events()
        observation = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { break }
                self?.receive(event)
            }
        }
        await refresh()
    }
    public func stop() {
        observation?.cancel(); observation = nil
        refreshTask?.cancel(); refreshTask = nil
        refreshGeneration += 1; completionGeneration += 1
        isRefreshing = false; eventsDuringRefresh = []
    }
    public func refresh() async {
        refreshRequested = true
        if let refreshTask { await refreshTask.value; return }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.refreshRequested = false
                await self.loadSnapshot()
            } while self.refreshRequested && !Task.isCancelled
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }
    private func loadSnapshot() async {
        error = nil
        refreshGeneration += 1
        let generation = refreshGeneration
        eventsDuringRefresh = []; isRefreshing = true
        defer { if generation == refreshGeneration { isRefreshing = false; eventsDuringRefresh = [] } }
        do {
            let snapshot = try await client.listNotes(filter: .all)
            let active = try await client.activeRecording()
            let preferences = try await client.settings()
            let playing = await client.playbackSnapshot()
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            notes = snapshot; recording = active; settings = preferences; playback = playing
            for event in eventsDuringRefresh { fold(event) }
            sortNotes(); revision += 1
            if let recording { elapsedSeconds = max(elapsedSeconds, Date().timeIntervalSince(recording.createdAt)) }
        } catch is CancellationError {} catch {
            if generation == refreshGeneration { self.error = IPhoneError(error) }
        }
    }
    public func perform(_ operation: () async throws -> Void) async {
        guard !isPending else { return }
        isPending = true; error = nil
        defer { isPending = false }
        do { try await operation(); await refresh() }
        catch is CancellationError {} catch { self.error = IPhoneError(error) }
    }
    public func startRecording() async {
        guard recording == nil else { return }
        await capture { _ = try await client.startRecording(source: .iphone) }
    }
    public func stopRecording() async {
        await capture {
            let note = try await client.stopRecording()
            if note == nil { feedback = "Short recording discarded" }
        }
    }
    public func dismissContextualPermissions() { offersContextualPermissions = false }
    public func discardRecording() async {
        await capture { try await client.discardRecording(); feedback = "Recording discarded" }
    }
    private func capture(_ operation: () async throws -> Void) async {
        guard !isRecordingPending else { return }; isRecordingPending = true; error = nil
        defer { isRecordingPending = false }
        do { try await operation(); await refresh() }
        catch is CancellationError {} catch { self.error = IPhoneError(error) }
    }
    private func receive(_ event: WhimEvent) {
        guard event.sequence > lastSequence else { return }
        let gap = event.sequence != lastSequence + 1
        lastSequence = event.sequence
        let finishingID = recording?.noteID
        if isRefreshing { eventsDuringRefresh.append(event) }
        fold(event)
        switch event.type {
        case .recordingStarted:
            completionGeneration += 1; offersContextualPermissions = false
            elapsedSeconds = 0; peakPowerDBFS = -160; feedback = "Recording started"
        case .recordingStopped:
            feedback = "Recording stopped"
            completionGeneration += 1
            let generation = completionGeneration
            if let finishingID, let uuid = UUID(uuidString: finishingID) {
                Task { [weak self, client] in
                    let saved = try? await client.note(id: NoteID(rawValue: uuid))
                    guard let self, generation == self.completionGeneration, saved != nil else { return }
                    self.feedback = "Note saved"; self.offersContextualPermissions = true
                }
            }
        case .recordingDiscarded, .notesReset:
            completionGeneration += 1; offersContextualPermissions = false
            feedback = event.type == .notesReset ? "" : "Recording discarded"
        default: break
        }
        if gap || event.type == .settingsChanged || event.type == .notesReset {
            Task { [weak self] in await self?.refresh() }
        }
    }
    private func fold(_ event: WhimEvent) {
        switch event.type {
        case .noteChanged:
            if let note = event.note { notes.removeAll { $0.id == note.id }; notes.append(note); sortNotes() }
        case .noteDeleted: notes.removeAll { $0.id.rawValue.uuidString.lowercased() == event.noteID }
        case .notesReset: notes = []; recording = nil; playback = nil
        case .recordingStarted: recording = event.recording; playback = nil
        case .recordingStopped, .recordingDiscarded: recording = nil
        case .recordingProgress:
            if let elapsed = event.elapsedSeconds { elapsedSeconds = elapsed }
            if let power = event.peakPowerDBFS { peakPowerDBFS = Double(power) }
        default: break
        }
        if event.type != .recordingProgress { revision += 1 }
    }
    private func sortNotes() {
        notes.sort { $0.createdAt == $1.createdAt ? $0.id.rawValue.uuidString < $1.id.rawValue.uuidString : $0.createdAt > $1.createdAt }
    }
}
