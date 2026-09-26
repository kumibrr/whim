import Foundation
#if os(watchOS)
import WidgetKit
#endif
#if canImport(Network)
import Network
#endif

public enum WhimServiceError: Error, Sendable, Equatable, CustomStringConvertible {
    case setupRequired(String)
    case invalidIdentifier(field: String)
    case invalidConfiguration(field: String)
    case permissionDenied
    case recordingActive
    case audioUnavailable

    public var description: String {
        switch self {
        case .setupRequired(let message): message
        case .invalidIdentifier: "The identifier is invalid."
        case .invalidConfiguration: "The webhook configuration is invalid."
        case .permissionDenied: "Microphone access is required. Open Settings to allow access."
        case .recordingActive: "Stop recording before playing a Note."
        case .audioUnavailable: "This Note's audio is unavailable."
        }
    }
}

public actor WhimService: WhimClient {
    private let peer: ConnectivityMergeService?
    private let recording: RecordingService
    private let store: any WhimStore
    private let files: any AudioFileManaging
    private let title: TitleService
    private let delivery: DeliveryService
    private let configuration: WebhookConfigurationService
    private let configurationTest: ConfigurationTestService
    private let recovery: RecoveryScanner
    private let preferences: any PreferenceStoring
    private let onboarding: any OnboardingStoring
    private var complicationObservation: Task<Void, Never>?
    private let permissions: any PermissionAdapter
    private let waveformAdapter: any AudioWaveformAdapter
    private let playback: any PlaybackAdapter
    private let credentials: any CredentialStore
    private let scheduler: any DeliveryScheduler
    private let clock: any Clock
    private let background: any BackgroundScheduling
    private let device: AttemptDevice
    private var retentionTask: Task<[NoteID], Error>?
    private nonisolated let eventBroadcaster = WhimEventBroadcaster()
    private var launchTask: Task<Void, Error>?
    private var maintenanceGeneration = 0
    private var maintenancePaused = false
    private var preparationTask: Task<RecoveryScanner.Inventory, Error>?
    private var recordingEventTask: Task<Void, Never>?
    private var deliveryEventTask: Task<Void, Never>?
    private struct Workflow: Sendable { let token: UUID; let task: Task<Void, Never> }
    private var workflows: [NoteID: Workflow] = [:]
    private struct ManualDelivery: Sendable { let token: UUID; let task: Task<Void, Error> }
    private var manualDeliveries: [NoteID: ManualDelivery] = [:]
    private var pendingDeliveryWakes: Set<NoteID> = []
    private var handledFinalizations: Set<NoteID> = []
    private var suppressedNoteIDs: Set<NoteID> = []
    private var resetInProgress = false
    private var sequence: UInt64 = 0
    private var commandRunning = false
    private var commandWaiters: [CheckedContinuation<Void, Never>] = []

    public init(recording: RecordingService, store: any WhimStore, files: any AudioFileManaging,
                title: TitleService, delivery: DeliveryService,
                configuration: WebhookConfigurationService,
                configurationTest: ConfigurationTestService, recovery: RecoveryScanner,
                preferences: any PreferenceStoring, credentials: any CredentialStore,
                scheduler: any DeliveryScheduler,
                onboarding: any OnboardingStoring = UserDefaultsOnboardingStore(),
                permissions: any PermissionAdapter = SystemPermissionAdapter(),
                playback: any PlaybackAdapter = SystemPlaybackAdapter(),
                peer: ConnectivityMergeService? = nil,
                waveform: any AudioWaveformAdapter = AVAudioWaveformAdapter(),
                clock: any Clock = SystemClock(),
                background: any BackgroundScheduling = NoBackgroundScheduler(),
                device: AttemptDevice = .iphone) {
        self.recording = recording; self.store = store; self.files = files; self.title = title
        self.delivery = delivery; self.configuration = configuration
        self.configurationTest = configurationTest; self.recovery = recovery
        self.preferences = preferences; self.credentials = credentials; self.scheduler = scheduler
        self.onboarding = onboarding
        self.permissions = permissions
        self.playback = playback
        self.waveformAdapter = waveform
        self.peer = peer
        self.clock = clock
        self.background = background; self.device = device
    }

    public nonisolated func events() -> AsyncStream<WhimEvent> { eventBroadcaster.stream() }

    /// Publish only meaningful recording and delivery transitions to the Watch extension.
    public func observeComplication(store: ComplicationStore, reload: @escaping @Sendable () -> Void) {
        complicationObservation?.cancel()
        complicationObservation = ComplicationPublisher(client: self, store: store, reload: reload).observe()
    }

    /// Only metadata enumeration and pending destructive reset precede capture.
    private func prepareCapture() async throws -> RecoveryScanner.Inventory {
        if maintenancePaused { await beginCommand(); endCommand() }
        if let preparationTask { return try await preparationTask.value }
        let task = Task {
            await self.beginRecordingEventsIfNeeded()
            await self.beginDeliveryEventsIfNeeded()
            if try await self.peer?.recoverReset() == true {
                try await self.background.replace(with: nil)
                await self.delivery.cancelNotifications()
                try await self.preferences.reset()
                await self.onboarding.reset()
                self.publish(.notesReset)
            }
            return try await self.recovery.inventory()
        }
        preparationTask = task
        do { return try await task.value }
        catch { preparationTask = nil; throw error }
    }

    public func startup() async throws -> StartupProjection {
        async let microphone = permissions.status(.microphone)
        _ = try await prepareCapture()
        async let completed = onboarding.isComplete()
        let active = await recording.snapshot().map(RecordingProjection.init)
        return await StartupProjection(onboardingCompleted: completed, microphone: microphone, recording: active)
    }

    public func maintain() async throws {
        try await launch()
        await beginCommand(); defer { endCommand() }
        try await runRetention()
    }

    public func performBackgroundMaintenance() async throws {
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await resumeDelivery()
                try Task.checkCancellation()
                while true {
                    let pending = workflows.values.map(\.task)
                    for task in pending { await task.value }
                    try Task.checkCancellation()
                    if try await finishBackgroundPass() { break }
                }
                try Task.checkCancellation()
                try await maintain()
            } onCancel: {
                Task { await self.expireBackgroundMaintenance() }
            }
        } catch {
            if Task.isCancelled { await expireBackgroundMaintenance() }
            throw error
        }
    }

    private func finishBackgroundPass() async throws -> Bool {
        await beginCommand(); defer { endCommand() }
        try Task.checkCancellation()
        let wakes = pendingDeliveryWakes
        pendingDeliveryWakes.removeAll()
        for id in wakes { try await resumeEligibleNotes(only: id) }
        return workflows.isEmpty && pendingDeliveryWakes.isEmpty
    }

    private func expireBackgroundMaintenance() async {
        await beginCommand()
        maintenancePaused = true
        defer { maintenancePaused = false; endCommand() }
        await cancelMaintenance()
        pendingDeliveryWakes.removeAll()
        let pending = workflows
        for workflow in pending.values { workflow.task.cancel() }
        for note in (try? await store.listNotes(filter: .all)) ?? [] {
            await title.cancel(noteID: note.id)
            await scheduler.cancel(noteID: note.id)
        }
        for workflow in pending.values { await workflow.task.value }
        try? await runRetention()
    }

    /// Full maintenance is single-flight, but never holds the capture command queue.
    public func launch() async throws {
        if maintenancePaused { await beginCommand(); endCommand() }
        if let launchTask { return try await launchTask.value }
        let beforePreparation = maintenanceGeneration
        let inventory = try await prepareCapture()
        if maintenancePaused || beforePreparation != maintenanceGeneration { return try await launch() }
        if let launchTask { return try await launchTask.value }
        let generation = maintenanceGeneration
        let task = Task {
            // Replay old peer mutations before validation; reset was handled during preparation.
            try await self.peer?.recoverPreparedState()
            try await self.recovery.scan(inventory)
            try await self.resumeEligibleNotes()
            for note in try await self.store.listNotes(filter: .all) { try await self.peer?.queueNote(note.id) }
            try await self.peer?.flush()
        }
        launchTask = task
        do { try await task.value }
        catch {
            if generation == maintenanceGeneration { launchTask = nil }
            throw error
        }
    }

    /// Call with the command queue held and new maintenance paused. Join before erasure.
    private func cancelMaintenance() async {
        maintenanceGeneration += 1
        let task = launchTask
        task?.cancel()
        _ = try? await task?.value
        _ = try? await preparationTask?.value
        launchTask = nil
    }

    public func receivePeer(_ event: PeerEvent) async throws {
        let destructive: Bool
        if case .message(let envelope) = event, case .reset = envelope.payload { destructive = true }
        else { destructive = false }
        if destructive {
            _ = try await prepareCapture()
            await beginCommand()
            maintenancePaused = true
            await cancelMaintenance()
        } else {
            try await launch()
            await beginCommand()
        }
        defer { if destructive { maintenancePaused = false; resetInProgress = false }; endCommand() }
        guard let peer else { return }
        let changed: NoteID?
        switch event {
        case .activated:
            try await peer.activated(); publish(.settingsChanged); return
        case .transferFailed(let id):
            try await peer.retryTransfer(id); return
        case .configuration(let envelope, let credentials):
            try await peer.receiveConfiguration(envelope, credentials: credentials)
            try await peer.flush()
            publish(.settingsChanged)
            try await resumeEligibleNotes(); return
        case .file(let url, let metadata):
            changed = try await peer.receiveFile(at: url, metadata: metadata)
            try await peer.completeReceivedFile(url)
        case .message(let envelope):
            let previousGeneration = try await peer.generation()
            switch envelope.payload {
            case .deletion(let id) where envelope.generation == previousGeneration:
                await quiesce(noteID: id)
                if await playback.snapshot()?.noteID == id.rawValue.uuidString.lowercased() { await playback.stop() }
            case .reset:
                // Higher-generation data cannot reach this destructive path.
                if envelope.generation > previousGeneration {
                    resetInProgress = true
                    await playback.stop()
                    try await recording.discard()
                    for note in try await store.listNotes(filter: .all) { await quiesce(noteID: note.id) }
                    _ = try? await retentionTask?.value
                    try await background.replace(with: nil)
                    await delivery.cancelNotifications()
                    try await preferences.reset(); await onboarding.reset()
                }
            default: break
            }
            changed = try await peer.apply(envelope)
            if case .reset = envelope.payload, envelope.generation > previousGeneration {
                preparationTask = nil
                publish(.notesReset)
            }
        }
        try await peer.flush()
        publish(.settingsChanged)
        guard let id = changed else { try await runRetention(); return }
        guard let note = try await store.note(id: id) else {
            publish(.noteDeleted, noteID: id.rawValue.uuidString.lowercased()); return
        }
        publish(.noteChanged, note: .init(note: note))
        if case .message(let envelope) = event {
            if case .title = envelope.payload { return }
            if case .receipt = envelope.payload { try await runRetention(); return }
        }
        if (note.isDeliveryEligible || (!note.requiresReview && note.titleSource != .transcription)),
           !suppressedNoteIDs.contains(id), workflows[id] == nil,
           manualDeliveries[id] == nil {
            startWorkflow(note)
        }
        try await runRetention()
    }

    public func resumeDelivery() async throws {
        try await launch(); await beginCommand(); defer { endCommand() }
        try await resumeEligibleNotes()
    }

    private func resumeEligibleNotes(only noteID: NoteID? = nil) async throws {
        guard !resetInProgress else { return }
        for projection in try await store.listNotes(filter: .all)
            where (noteID == nil || projection.id == noteID)
                && !projection.requiresReview && projection.workflowError == nil
                && (projection.status == .queued || projection.status == .sending) {
            guard !suppressedNoteIDs.contains(projection.id) else { continue }
            if workflows[projection.id] != nil {
                pendingDeliveryWakes.insert(projection.id)
                continue
            }
            guard let note = try await store.note(id: projection.id) else { continue }
            startWorkflow(note)
        }
    }

    private func replayDeliveryWake(noteID: NoteID) async throws {
        await beginCommand(); defer { endCommand() }
        guard pendingDeliveryWakes.remove(noteID) != nil else { return }
        try await resumeEligibleNotes(only: noteID)
    }

    public func startRecording(source: CaptureSource) async throws -> RecordingProjection {
        _ = try await prepareCapture(); await beginCommand(); defer { endCommand() }
        let permission = await permissions.status(.microphone)
        guard permission == .granted || permission == .unavailable else { throw WhimServiceError.permissionDenied }
        await playback.stop()
        let projection = RecordingProjection(try await recording.start(source: source))
        publish(.recordingStarted, recording: projection)
        return projection
    }

    public func activeRecording() async throws -> RecordingProjection? {
        _ = try await prepareCapture(); await beginCommand(); defer { endCommand() }
        return await recording.snapshot().map(RecordingProjection.init)
    }

    public func stopRecording() async throws -> NoteProjection? {
        _ = try await prepareCapture(); await beginCommand(); defer { endCommand() }
        guard let finalized = try await recording.stop() else { return nil }
        handleFinalized(finalized)
        return NoteProjection(note: finalized)
    }

    public func discardRecording() async throws {
        _ = try await prepareCapture(); await beginCommand(); defer { endCommand() }
        try await recording.discard(); publish(.recordingDiscarded)
    }

    public func listNotes(filter: NoteFilter) async throws -> [NoteProjection] {
        _ = try await prepareCapture()
        return try await store.listNotes(filter: filter)
    }

    public func note(id: NoteID) async throws -> NoteDetailProjection? {
        _ = try await prepareCapture()
        guard let note = try await store.note(id: id) else { return nil }
        let attempts = try await store.deliveryAttempts(noteID: id)
        return NoteDetailProjection(note: note, hasLocalAudio: files.audioError(at: note.audioURL) == nil, deliveryAttempts: attempts)
    }

    public func webhookErrors() async throws -> [WebhookErrorProjection] {
        _ = try await prepareCapture()
        var errors: [WebhookErrorProjection] = []
        for summary in try await store.listNotes(filter: .all) {
            guard let note = try await store.note(id: summary.id) else { continue }
            errors += note.delivery.failedAttempts.map { WebhookErrorProjection(note: note, failure: $0) }
        }
        return errors.sorted { $0.failedAt > $1.failedAt }
    }

    public func retry(noteID: NoteID) async throws {
        try await runManualDelivery(noteID: noteID, recovered: false)
    }

    public func retryAllFailed() async throws -> Int {
        let notes = try await listNotes(filter: .failed)
        for note in notes { try await retry(noteID: note.id) }
        return notes.count
    }

    public func sendRecovered(noteID: NoteID) async throws {
        try await runManualDelivery(noteID: noteID, recovered: true)
    }

    /// Register under the command lock, then await HTTP outside it. Capture commands
    /// stay responsive and destructive commands can cancel and join this work.
    private func runManualDelivery(noteID: NoteID, recovered: Bool) async throws {
        try await launch()
        await beginCommand()
        let operation: ManualDelivery
        do {
            if let existing = manualDeliveries[noteID] {
                operation = existing
            } else {
                if recovered { try await store.send(noteID: noteID) }
                let token = UUID()
                let delivery = delivery
                let task = Task { [weak self] in
                    if recovered { _ = try await delivery.deliver(noteID: noteID) }
                    else { _ = try await delivery.retry(noteID: noteID) }
                    try await self?.manualDeliveryUpdated(noteID: noteID, token: token)
                }
                operation = ManualDelivery(token: token, task: task)
                manualDeliveries[noteID] = operation
            }
        } catch {
            endCommand()
            throw error
        }
        endCommand()
        defer {
            if manualDeliveries[noteID]?.token == operation.token { manualDeliveries[noteID] = nil }
        }
        try await withTaskCancellationHandler {
            try await operation.task.value
        } onCancel: { operation.task.cancel() }
    }

    private func manualDeliveryUpdated(noteID: NoteID, token: UUID) async throws {
        let note = try await store.note(id: noteID)
        guard manualDeliveries[noteID]?.token == token, !resetInProgress,
              !suppressedNoteIDs.contains(noteID), let note else { return }
        publish(.noteChanged, note: .init(note: note))
        try await peer?.queueNote(noteID)
    }

    public func delete(noteID: NoteID) async throws {
        _ = try await prepareCapture()
        await beginCommand()
        maintenancePaused = true
        defer { maintenancePaused = false; endCommand() }
        await cancelMaintenance()
        if await playback.snapshot()?.noteID == noteID.rawValue.uuidString.lowercased() { await playback.stop() }
        let existing = try await store.note(id: noteID)
        await quiesce(noteID: noteID)
        try await store.delete(noteID: noteID)
        if existing != nil { try files.delete(noteID: noteID) }
        try await peer?.queueDeletion(noteID)
        publish(.noteDeleted, noteID: noteID.rawValue.uuidString.lowercased())
        try await runRetention()
    }

    public func updateWebhook(_ input: WebhookConfigurationInput) async throws -> ConfigurationUpdateResult {
        try await launch(); await beginCommand(); defer { endCommand() }
        let counts: ConfigurationSaveCounts
        do { counts = try await configuration.save(input) }
        catch let error as WebhookConfigurationSaveError {
            if case .invalid(let errors) = error {
                throw WhimServiceError.invalidConfiguration(field: Self.field(errors.first?.field))
            }
            throw error
        }
        guard let revision = try await store.latestConfigurationRevision() else {
            throw WhimServiceError.setupRequired("The saved webhook revision is unavailable.")
        }
        for projection in try await store.listNotes(filter: .all) { publish(.noteChanged, note: projection) }
        try await peer?.flush()
        try await runRetention()
        return ConfigurationUpdateResult(revisionID: revision.id, failedCount: counts.failed,
            setupRequiredCount: counts.awaitingSetup)
    }

    public func testWebhook() async throws -> ConfigurationTestResult {
        _ = try await prepareCapture()
        guard let revision = try await store.latestConfigurationRevision() else {
            throw ConfigurationTestError.missingConfiguration
        }
        return try await configurationTest.send(revisionID: revision.id)
    }

    public func updatePreferences(_ input: PreferenceInput) async throws {
        try await launch(); await beginCommand(); defer { endCommand() }
        try await preferences.save(input)
        try await runRetention()
    }

    public func settings() async throws -> SettingsProjection {
        _ = try await prepareCapture()
        async let microphone = permissions.status(.microphone)
        async let speech = permissions.status(.speech)
        async let notifications = permissions.status(.notifications)
        async let input = preferences.load()
        async let completed = onboarding.isComplete()
        async let watch = peer?.status() ?? .unavailable
        var webhook: WebhookSettingsProjection?
        if let revision = try await store.latestConfigurationRevision(),
           let secrets = try await credentials.credentials(for: revision.id) {
            webhook = .init(revision: revision, credentials: secrets)
        }
        return try await .init(preferences: input, webhook: webhook,
            onboardingCompleted: completed, permissions: .init(
                microphone: microphone, speech: speech, notifications: notifications), watch: watch)
    }

    public func completeOnboarding() async throws {
        _ = try await prepareCapture(); await beginCommand(); defer { endCommand() }
        await onboarding.complete()
    }

    public func requestPermission(_ kind: PermissionKind) async throws -> PermissionStatus {
        let current = await permissions.status(kind)
        guard current == .notDetermined else { return current }
        return try await permissions.request(kind)
    }

    public func openSystemSettings() async throws { try await permissions.openSettings() }

    public func waveform(noteID: NoteID) async throws -> AudioWaveform {
        _ = try await prepareCapture()
        guard let note = try await store.note(id: noteID), note.localError == nil,
              files.audioError(at: note.audioURL) == nil else { return .unavailable }
        do {
            let samples = try await waveformAdapter.waveform(at: note.audioURL)
            try Task.checkCancellation()
            guard let current = try await store.note(id: noteID), current.localError == nil,
                  current.audioURL == note.audioURL, files.audioError(at: current.audioURL) == nil else {
                return .unavailable
            }
            return .samples(samples)
        } catch is CancellationError { throw CancellationError() }
        catch { return .unavailable }
    }

    public func playNote(_ id: NoteID) async throws -> PlaybackProjection {
        _ = try await prepareCapture(); await beginCommand(); defer { endCommand() }
        guard await recording.snapshot() == nil else { throw WhimServiceError.recordingActive }
        guard let note = try await store.note(id: id), note.localError == nil,
              files.audioError(at: note.audioURL) == nil else { throw WhimServiceError.audioUnavailable }
        return try await playback.play(noteID: id, url: note.audioURL)
    }
    public func stopPlayback() async { await playback.stop() }
    public func playbackSnapshot() async -> PlaybackProjection? { await playback.snapshot() }

    public func patchWebhook(_ patch: WebhookPatch) async throws -> ConfigurationUpdateResult {
        try await launch(); await beginCommand(); defer { endCommand() }
        var existing: StoredWebhookCredentials?
        if let revision = try await store.latestConfigurationRevision() {
            existing = try await credentials.credentials(for: revision.id)
        }
        let counts: ConfigurationSaveCounts
        do { counts = try await configuration.save(patch.applying(to: existing)) }
        catch let error as WebhookConfigurationSaveError {
            if case .invalid(let errors) = error { throw WhimServiceError.invalidConfiguration(field: Self.field(errors.first?.field)) }
            throw error
        }
        guard let revision = try await store.latestConfigurationRevision() else { throw WhimServiceError.setupRequired("Configuration unavailable.") }
        for projection in try await store.listNotes(filter: .all) { publish(.noteChanged, note: projection) }
        try await peer?.flush()
        return .init(revisionID: revision.id, failedCount: counts.failed, setupRequiredCount: counts.awaitingSetup)
    }

    public func reset() async throws {
        await beginCommand()
        maintenancePaused = true
        defer { maintenancePaused = false; endCommand() }
        resetInProgress = true
        await cancelMaintenance()
        await playback.stop()
        defer { resetInProgress = false }
        try await recording.discard()
        let notes = try await store.listNotes(filter: .all)
        let sessions = try await store.recordingSessions()
        for note in notes { await quiesce(noteID: note.id) }
        _ = try? await retentionTask?.value
        try await background.replace(with: nil)
        await delivery.cancelNotifications()
        let resetEnvelope = try await peer?.prepareReset()
        for note in notes {
            try await store.delete(noteID: note.id)
            try files.delete(noteID: note.id)
        }
        for session in sessions { try files.deleteTemporary(sessionID: session.id) }
        try await store.reset()
        try await credentials.removeAll()
        try await preferences.reset()
        await onboarding.reset()
        if let resetEnvelope { _ = try await peer?.apply(resetEnvelope) }
        preparationTask = nil
        try await peer?.flush()
        publish(.notesReset)
    }

    private func publishCurrent(_ noteID: NoteID) async throws {
        if let note = try await store.note(id: noteID) { publish(.noteChanged, note: .init(note: note)) }
    }

    private func beginRecordingEventsIfNeeded() async {
        guard recordingEventTask == nil else { return }
        let stream = await recording.events()
        recordingEventTask = Task { [weak self] in
            for await event in stream { await self?.publish(event) }
        }
    }

    private func beginDeliveryEventsIfNeeded() async {
        guard deliveryEventTask == nil else { return }
        let stream = delivery.events()
        deliveryEventTask = Task { [weak self] in
            for await noteID in stream { await self?.workerUpdated(noteID: noteID, token: nil) }
        }
    }

    private func publish(_ event: RecordingServiceEvent) {
        switch event {
        case .elapsed(let value): publish(.recordingProgress, elapsedSeconds: value)
        case .signal(let signal): publish(.recordingProgress, peakPowerDBFS: signal.peakPowerDBFS, recordingTone: signal.tone)
        case .peakPower(let value): publish(.recordingProgress, peakPowerDBFS: value)
        case .routeChanged: publish(.recordingRouteChanged)
        case .maximumDurationWarning: publish(.recordingMaximumDurationWarning)
        case .finalized(let note): handleFinalized(note)
        case .finalizationFailed: publish(.recordingStopped)
        }
    }

    private func handleFinalized(_ note: Note?) {
        guard let note else { publish(.recordingStopped); return }
        guard !resetInProgress, !suppressedNoteIDs.contains(note.id),
              handledFinalizations.insert(note.id).inserted else { return }
        publish(.recordingStopped)
        publish(.noteChanged, note: .init(note: note))
        startWorkflow(note)
    }

    private func startWorkflow(_ note: Note) {
        let token = UUID()
        let title = title
        let delivery = delivery
        let peer = peer
        let task = Task { [weak self] in
            // Persist the background handoff before starting either local step.
            try? await peer?.queueNote(note.id)
            let titleStep = Task { [weak self] in
                _ = await title.complete(note)
                await self?.workerUpdated(noteID: note.id, token: token)
            }
            let deliveryStep = Task { [weak self] in
                do { _ = try await delivery.deliver(noteID: note.id) }
                catch is CancellationError { return }
                catch {
                    await self?.workerFailed(noteID: note.id, token: token)
                    return
                }
                await self?.workerUpdated(noteID: note.id, token: token)
            }
            await withTaskCancellationHandler {
                await titleStep.value
                await deliveryStep.value
            } onCancel: {
                titleStep.cancel()
                deliveryStep.cancel()
            }
            await self?.workerFinished(noteID: note.id, token: token)
        }
        workflows[note.id] = Workflow(token: token, task: task)
    }

    private func workerUpdated(noteID: NoteID, token: UUID?) async {
        guard !resetInProgress, !suppressedNoteIDs.contains(noteID) else { return }
        if let token, workflows[noteID]?.token != token { return }
        try? await peer?.queueNote(noteID)
        try? await runRetention()
        try? await publishCurrent(noteID)
    }

    private func runRetention() async throws {
        guard !resetInProgress else { return }
        let previous = retentionTask
        let activeNotes = Set(workflows.keys)
        let task = Task {
            _ = try? await previous?.value
            let pendingHandoffs = try await peer?.pendingAudioNoteIDs() ?? []
            return try await MaintenanceService(store: store, files: files, preferences: preferences,
                background: background, device: device)
                .run(now: clock.now, preserving: activeNotes.union(pendingHandoffs))
        }
        retentionTask = task
        let expired = try await task.value
        for id in expired { try await publishCurrent(id) }
    }

    private func workerFinished(noteID: NoteID, token: UUID) async {
        guard workflows[noteID]?.token == token else { return }
        workflows[noteID] = nil
        if !resetInProgress { try? await runRetention() }
        if pendingDeliveryWakes.contains(noteID) {
            // Join the command queue after this workflow returns, so Reset/Delete can
            // await its completion without waiting on their own command lock.
            Task { [weak self] in try? await self?.replayDeliveryWake(noteID: noteID) }
        }
    }

    private func workerFailed(noteID: NoteID, token: UUID) async {
        guard workflows[noteID]?.token == token else { return }
        try? await publishCurrent(noteID)
    }

    private func quiesce(noteID: NoteID) async {
        suppressedNoteIDs.insert(noteID)
        pendingDeliveryWakes.remove(noteID)
        let workflow = workflows[noteID]
        let manual = manualDeliveries[noteID]
        workflow?.task.cancel()
        manual?.task.cancel()
        async let titleCancellation: Void = title.cancel(noteID: noteID)
        async let schedulerCancellation: Void = scheduler.cancel(noteID: noteID)
        _ = await (titleCancellation, schedulerCancellation)
        await workflow?.task.value
        _ = try? await manual?.task.value
        if manualDeliveries[noteID]?.token == manual?.token { manualDeliveries[noteID] = nil }
        if workflows[noteID]?.token == workflow?.token { workflows[noteID] = nil }
    }

    private func publish(_ type: WhimEvent.Kind, recording: RecordingProjection? = nil,
                         note: NoteProjection? = nil, noteID: String? = nil,
                         elapsedSeconds: TimeInterval? = nil, peakPowerDBFS: Float? = nil, recordingTone: Float? = nil) {
        sequence += 1
        eventBroadcaster.yield(.init(sequence: sequence, type: type, recording: recording,
            note: note, noteID: noteID, elapsedSeconds: elapsedSeconds, peakPowerDBFS: peakPowerDBFS, recordingTone: recordingTone))
    }

    private func beginCommand() async {
        if !commandRunning { commandRunning = true; return }
        await withCheckedContinuation { commandWaiters.append($0) }
    }

    private func endCommand() {
        if commandWaiters.isEmpty { commandRunning = false }
        else { commandWaiters.removeFirst().resume() }
    }

    private static func field(_ value: WebhookValidationField?) -> String {
        switch value {
        case .endpoint: "endpoint"; case .customHeaders: "customHeaders"
        case .customHeader(let index): "customHeaders[\(index)]"; case nil: "configuration"
        }
    }
}

private final class WhimEventBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<WhimEvent>.Continuation] = [:]

    func stream() -> AsyncStream<WhimEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.withLock { continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.continuations[id] = nil }
            }
        }
    }

    func yield(_ event: WhimEvent) {
        lock.withLock { Array(continuations.values) }.forEach { $0.yield(event) }
    }
}

public final class UserDefaultsPreferenceStore: PreferenceStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    private let key = "preferences.v1"

    public init(suiteName: String) throws {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw WhimServiceError.setupRequired("Shared preferences are unavailable.")
        }
        self.defaults = defaults
    }
    public func load() throws -> PreferenceInput {
        try lock.withLock {
            guard let data = defaults.data(forKey: key) else { return .default }
            return try JSONDecoder().decode(PreferenceInput.self, from: data)
        }
    }
    public func save(_ input: PreferenceInput) throws {
        try lock.withLock { defaults.set(try JSONEncoder().encode(input), forKey: key) }
    }
    public func reset() { lock.withLock { defaults.removeObject(forKey: key) } }
}

public enum WhimProductionComposition {
    #if os(watchOS)
    public static let appGroupIdentifier = "group.app.whim.watch.shared"
    private static let credentialService = "app.whim.watch.webhook"
    private static let deliveryDevice: AttemptDevice = .appleWatch
    #else
    public static let appGroupIdentifier = "group.app.whim.shared"
    private static let credentialService = "app.whim.webhook"
    private static let deliveryDevice: AttemptDevice = .iphone
    #endif

    public static func make(bundle: Bundle = .main) async throws -> WhimService {
        let root = try sharedRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try SQLiteWhimStore.open(at: root.appendingPathComponent("whim.sqlite"))
        var suiteName = appGroupIdentifier
        var keychainService = credentialService
        var permissions: any PermissionAdapter = SystemPermissionAdapter()
        #if DEBUG && os(watchOS)
        if let testID = watchTestID {
            suiteName += ".test." + testID
            keychainService += ".test." + testID
            permissions = DebugWatchPermissions()
        }
        #endif
        let recorder: any AudioRecorder
        #if DEBUG && os(watchOS)
        if watchTestID != nil {
            recorder = try DebugFixtureRecorder.from(arguments: ProcessInfo.processInfo.arguments)
                ?? DebugFixtureRecorder(fixture: configurationTestFixtureURL(bundle: bundle))
        } else {
            recorder = try DebugFixtureRecorder.from(arguments: ProcessInfo.processInfo.arguments) ?? AVAudioRecorderAdapter()
        }
        #elseif DEBUG
        recorder = try DebugFixtureRecorder.from(arguments: ProcessInfo.processInfo.arguments) ?? AVAudioRecorderAdapter()
        #else
        recorder = AVAudioRecorderAdapter()
        #endif
        let files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        #if canImport(ActivityKit) && os(iOS)
        let activity = LiveActivityAdapter(system: ActivityKitRecordingSystem())
        await activity.reconcile(activeSessionID: nil)
        let recording = RecordingService(recorder: recorder, store: store, files: files, activity: activity)
        #else
        let recording = RecordingService(recorder: recorder, store: store, files: files)
        #endif
        #if canImport(Speech) && !os(watchOS)
        let transcriber: any Transcriber = OnDeviceTranscriber()
        #else
        let transcriber: any Transcriber = UnavailableTranscriber()
        #endif
        let preferences = try UserDefaultsPreferenceStore(suiteName: suiteName)
        let preferenceAwareTranscriber = PreferenceAwareTranscriber(base: transcriber, preferences: preferences)
        let title = TitleService(transcriber: preferenceAwareTranscriber, store: store, locale: {
            let input = (try? preferences.load()) ?? .default
            return input.transcriptionEnabled
                ? input.transcriptionLocaleIdentifier.map(Locale.init(identifier:)) ?? .current
                : Locale(identifier: "und")
        })
        let credentials = KeychainCredentialStore(service: keychainService)
        let transport: any HTTPTransport
        #if DEBUG
        transport = try DebugFixtureTransport.from(arguments: ProcessInfo.processInfo.arguments, base: URLSessionHTTPTransport()) ?? URLSessionHTTPTransport()
        #else
        transport = URLSessionHTTPTransport()
        #endif
        let scheduler = InProcessDeliveryScheduler()
        let connectivity = SystemConnectivity()
        let notifications = LocalNotificationAdapter()
        let info = bundle.infoDictionary
        let delivery = DeliveryService(store: store, credentials: credentials, transport: transport,
            notifications: notifications, scheduler: scheduler,
            isConnected: { connectivity.isConnected }, titleSnapshot: { await title.enrich($0) },
            scheduledFailure: { noteID, error in
                guard !(error is CancellationError) else { return }
                await notifications.notifyFailure(title: "Whim delivery",
                    reason: "Delivery could not continue until it is retried.", noteID: noteID)
            }, device: deliveryDevice, appVersion: info?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            appBuild: info?["CFBundleVersion"] as? String ?? "1")
        let configuration = WebhookConfigurationService(store: store, credentials: credentials)
        let configurationTest = ConfigurationTestService(credentials: credentials, transport: transport,
            fixtureAudio: { try configurationTestFixtureURL(bundle: bundle) },
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            appBuild: info?["CFBundleVersion"] as? String ?? "1")
        var peerTransport: (any PeerTransport)?
        #if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
        peerTransport = WatchConnectivityAdapter(session: try SystemWatchConnectivitySession(receivedRoot: root.appendingPathComponent("PeerReceived"), databaseURL: root.appendingPathComponent("whim.sqlite")))
        #else
        peerTransport = nil
        #endif
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let peerFixtureFlags = ["-WhimPeerScenario", "-WhimFixtureAudio", "-WhimFixtureWebhookURL", "-WhimWatchTestID"]
        if arguments.contains(where: peerFixtureFlags.contains),
           let debugPeer = try DebugPeerTransport.from(arguments: arguments,
                fixture: configurationTestFixtureURL(bundle: bundle)) { peerTransport = debugPeer }
        #endif
        let peer = try ConnectivityMergeService(store: store, files: files,
            databaseURL: root.appendingPathComponent("whim.sqlite"), root: root.appendingPathComponent("Peer"),
            device: deliveryDevice, credentials: credentials, transport: peerTransport)
        var playback: any PlaybackAdapter = SystemPlaybackAdapter()
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-WhimPlaybackFailureOnce") {
            playback = DebugRetryPlaybackAdapter(base: playback)
        }
        #endif
        #if os(iOS)
        let background: any BackgroundScheduling = BGTaskSchedulerAdapter()
        #elseif os(watchOS)
        let background: any BackgroundScheduling = await WatchBackgroundScheduler.shared
        #else
        let background: any BackgroundScheduling = NoBackgroundScheduler()
        #endif
        let service = WhimService(recording: recording, store: store, files: files, title: title,
            delivery: delivery, configuration: configuration, configurationTest: configurationTest,
            recovery: RecoveryScanner(store: store, files: files), preferences: preferences,
            credentials: credentials, scheduler: scheduler,
            onboarding: UserDefaultsOnboardingStore(suiteName: suiteName), permissions: permissions, playback: playback, peer: peer,
            background: background, device: deliveryDevice)
        #if DEBUG && os(watchOS)
        if watchTestID != nil, ProcessInfo.processInfo.arguments.contains("-WhimWatchConfigured"),
           try await store.latestConfigurationRevision() == nil {
            _ = try await configuration.save(.init(endpoint: "https://whim-fixture.invalid/receive"))
        }
        #endif
        peerTransport?.activate { [weak service] event in
            let background = WatchBackgroundTaskCoordinator.shared
            background.beginProcessing()
            Task {
                defer { background.endProcessing() }
                try? await service?.receivePeer(event)
            }
        }
        connectivity.onReconnect { [weak service] in
            Task { try? await service?.resumeDelivery() }
        }
        #if os(watchOS)
        await service.observeComplication(store: ComplicationStore(url: root.appendingPathComponent("complication.json"))) {
            WidgetCenter.shared.reloadTimelines(ofKind: "app.whim.recording")
        }
        #endif
        return service
    }

    #if DEBUG && os(watchOS)
    private static var watchTestID: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-WhimWatchTestID"), args.indices.contains(index + 1),
              let id = UUID(uuidString: args[index + 1]) else { return nil }
        return id.uuidString
    }
    #endif

    public static func sharedRoot() throws -> URL {
        #if DEBUG && os(watchOS)
        if let testID = watchTestID {
            return FileManager.default.temporaryDirectory.appendingPathComponent("WhimWatchTests/" + testID)
        }
        #endif
        if let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return root.appendingPathComponent("Whim", isDirectory: true)
        }
        #if DEBUG && targetEnvironment(simulator)
        let applicationSupport = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        return applicationSupport.appendingPathComponent("Whim-Debug-Simulator", isDirectory: true)
        #else
        throw WhimServiceError.setupRequired("The Whim shared App Group is unavailable.")
        #endif
    }

    private static func configurationTestFixtureURL(bundle: Bundle) throws -> URL {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "configuration-test-fixture", withExtension: "m4a") { return url }
        #endif
        if let url = bundle.url(forResource: "configuration-test-fixture", withExtension: "m4a") { return url }
        if let resourceBundle = bundle.url(forResource: "WhimCoreConfigurationTest", withExtension: "bundle")
            .flatMap(Bundle.init(url:)),
           let url = resourceBundle.url(forResource: "configuration-test-fixture", withExtension: "m4a") { return url }
        throw WhimServiceError.setupRequired("The configuration-test audio asset is unavailable.")
    }
}

private struct UnavailableTranscriber: Transcriber {
    func transcribe(audioAt url: URL, locale: Locale) async throws -> String {
        throw TranscriptionError.unavailable
    }
}

private struct PreferenceAwareTranscriber: Transcriber {
    let base: any Transcriber
    let preferences: any PreferenceStoring
    func transcribe(audioAt url: URL, locale: Locale) async throws -> String {
        guard try await preferences.load().transcriptionEnabled else { throw TranscriptionError.unavailable }
        return try await base.transcribe(audioAt: url, locale: locale)
    }
}

private final class SystemConnectivity: @unchecked Sendable {
    private let lock = NSLock()
    private var connected = true
    private var reconnect: (@Sendable () -> Void)?
    #if canImport(Network)
    private let monitor = NWPathMonitor()
    #endif
    init() {
        #if canImport(Network)
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let callback = self.lock.withLock { () -> (@Sendable () -> Void)? in
                let wasConnected = self.connected
                self.connected = path.status == .satisfied
                return self.connected && !wasConnected ? self.reconnect : nil
            }
            callback?()
        }
        monitor.start(queue: DispatchQueue(label: "app.whim.connectivity"))
        #endif
    }
    var isConnected: Bool {
        #if DEBUG
        if DebugFixtureTransport.offline { return false }
        #endif
        return lock.withLock { connected }
    }
    func onReconnect(_ callback: @escaping @Sendable () -> Void) {
        let connected = lock.withLock { reconnect = callback; return self.connected }
        if connected { callback() }
    }
}

#if DEBUG && os(watchOS)
private struct DebugWatchPermissions: PermissionAdapter {
    func status(_ kind: PermissionKind) async -> PermissionStatus {
        guard kind == .microphone else { return .unavailable }
        return ProcessInfo.processInfo.arguments.contains("-WhimWatchMicrophoneDenied") ? .denied : .granted
    }
    func request(_ kind: PermissionKind) async throws -> PermissionStatus { await status(kind) }
    func openSettings() async throws {}
}
#endif

#if DEBUG && targetEnvironment(simulator)
/// Installed UI tests exercise a real player after one injected system-boundary failure.
private actor DebugRetryPlaybackAdapter: PlaybackAdapter {
    let base: any PlaybackAdapter
    private var failed = false
    init(base: any PlaybackAdapter) { self.base = base }
    func play(noteID: NoteID, url: URL) async throws -> PlaybackProjection {
        if !failed { failed = true; throw NSError(domain: "WhimPlaybackFixture", code: 1) }
        return try await base.play(noteID: noteID, url: url)
    }
    func stop() async { await base.stop() }
    func snapshot() async -> PlaybackProjection? { await base.snapshot() }
}
#endif
