import Foundation

public struct RecordingSnapshot: Sendable, Equatable {
    public let sessionID: RecordingSessionID
    public let noteID: NoteID
    public let source: CaptureSource
    public let createdAt: Date

    public init(sessionID: RecordingSessionID, noteID: NoteID, source: CaptureSource, createdAt: Date) {
        self.sessionID = sessionID
        self.noteID = noteID
        self.source = source
        self.createdAt = createdAt
    }
}

/// UI-safe progress shared by iPhone, Watch, and Live Activity clients.
public enum RecordingServiceEvent: Sendable, Equatable {
    case elapsed(TimeInterval)
    case peakPower(Float)
    case routeChanged
    case maximumDurationWarning
    case finalized(Note?)
    case finalizationFailed
}

public enum RecordingServiceError: Error, Sendable, Equatable {
    case encoderFailed
    case eventStreamEnded
}

/// System boundary for the activity associated with one canonical Recording Session.
/// Implementations must make ending an absent or already-ended session harmless.
public protocol RecordingActivityManaging: Sendable {
    func start(_ recording: RecordingSnapshot) async throws
    func end(sessionID: RecordingSessionID) async
}

public actor RecordingService {
    private typealias EncoderMetrics = (duration: TimeInterval, peakPowerDBFS: Float)

    private let activity: (any RecordingActivityManaging)?
    private let recorder: any AudioRecorder
    private let store: any WhimStore
    private let files: any AudioFileManaging
    private let now: @Sendable () -> Date
    private let timestampTitle: @Sendable (Date) -> String
    private let serviceEvents: AsyncStream<RecordingServiceEvent>
    private let serviceEventContinuation: AsyncStream<RecordingServiceEvent>.Continuation
    private var active: RecordingSnapshot?
    private var activating: RecordingSnapshot?
    private var startTask: Task<RecordingSnapshot, Error>?
    private var recorderEventTask: Task<Void, Never>?
    private var finalizationTask: Task<Note?, Error>?
    private var discardTask: Task<Void, Error>?
    private var encoderCompletion: EncoderMetrics?
    private var encoderFailure: RecordingServiceError?
    private var encoderWaiter: CheckedContinuation<EncoderMetrics, Error>?
    private var recorderStreamEnded = false
    private var warningEmitted = false
    private var maximumStopRequested = false
    private var interruptionDuringActivation = false

    public init(
        recorder: any AudioRecorder,
        store: any WhimStore,
        files: any AudioFileManaging,
        activity: (any RecordingActivityManaging)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        timestampTitle: @escaping @Sendable (Date) -> String = {
            $0.formatted(date: .abbreviated, time: .shortened)
        }
    ) {
        self.activity = activity
        self.recorder = recorder
        self.store = store
        self.files = files
        self.now = now
        self.timestampTitle = timestampTitle
        let pair = AsyncStream.makeStream(of: RecordingServiceEvent.self)
        serviceEvents = pair.stream
        serviceEventContinuation = pair.continuation
    }

    public func events() -> AsyncStream<RecordingServiceEvent> { serviceEvents }
    public func snapshot() -> RecordingSnapshot? { active ?? activating }

    public func start(source: CaptureSource) async throws -> RecordingSnapshot {
        if let discardTask { try await discardTask.value }
        if let active { return active }
        if let startTask { return try await startTask.value }

        let snapshot = RecordingSnapshot(sessionID: RecordingSessionID(), noteID: NoteID(),
            source: source, createdAt: now())
        let task = Task { try await self.activate(snapshot) }
        startTask = task
        do {
            let started = try await task.value
            startTask = nil
            return started
        } catch {
            startTask = nil
            throw error
        }
    }

    private func activate(_ snapshot: RecordingSnapshot) async throws -> RecordingSnapshot {
        let session = RecordingSession(id: snapshot.sessionID, noteID: snapshot.noteID,
            createdAt: snapshot.createdAt, source: snapshot.source)
        do {
            try await store.saveRecordingSession(session)
            encoderCompletion = nil
            encoderFailure = nil
            encoderWaiter = nil
            warningEmitted = false
            maximumStopRequested = false
            interruptionDuringActivation = false
            activating = snapshot
            try await activity?.start(snapshot)
            beginConsumingRecorderEvents()
            try await recorder.start(at: files.temporaryURL(for: snapshot.sessionID))
            active = snapshot
            activating = nil
            if interruptionDuringActivation {
                interruptionDuringActivation = false
                Task { try? await self.handleInterruption() }
            }
            return snapshot
        } catch {
            activating = nil
            interruptionDuringActivation = false
            encoderCompletion = nil
            encoderFailure = nil
            encoderWaiter = nil
            await recorder.discard()
            await activity?.end(sessionID: snapshot.sessionID)
            try? files.deleteTemporary(sessionID: snapshot.sessionID)
            try? await store.discardRecordingSession(sessionID: snapshot.sessionID)
            throw error
        }
    }

    public func stop() async throws -> Note? {
        try await beginFinalization(outcome: .completed)
    }

    public func handleInterruption() async throws -> Note? {
        try await beginFinalization(outcome: .interrupted)
    }

    private func beginFinalization(outcome: CaptureOutcome) async throws -> Note? {
        if let discardTask {
            try await discardTask.value
            return nil
        }
        if let startTask { _ = try await startTask.value }
        if let finalizationTask { return try await finalizationTask.value }
        guard let snapshot = active else { return nil }

        let task = Task { try await self.finalize(snapshot, outcome: outcome) }
        finalizationTask = task
        do {
            let note = try await task.value
            finalizationTask = nil
            return note
        } catch {
            finalizationTask = nil
            throw error
        }
    }

    public func discard() async throws {
        if let discardTask { return try await discardTask.value }
        if let startTask { _ = try await startTask.value }
        if let finalizationTask {
            _ = try await finalizationTask.value
            return
        }
        guard let snapshot = active else { return }
        active = nil
        let task = Task { try await self.performDiscard(snapshot) }
        discardTask = task
        do {
            try await task.value
            discardTask = nil
        } catch {
            discardTask = nil
            throw error
        }
    }

    private func performDiscard(_ snapshot: RecordingSnapshot) async throws {
        await recorder.discard()
        await activity?.end(sessionID: snapshot.sessionID)
        try files.deleteTemporary(sessionID: snapshot.sessionID)
        try await store.discardRecordingSession(sessionID: snapshot.sessionID)
    }

    private func beginConsumingRecorderEvents() {
        guard recorderEventTask == nil else { return }
        let recorder = recorder
        recorderEventTask = Task { [weak self] in
            let events = await recorder.events()
            for await event in events { await self?.consume(event) }
            await self?.recorderEventsEnded()
        }
    }

    private func consume(_ event: RecordingEvent) {
        let captureExists = active != nil || activating != nil
        switch event {
        case .elapsed(let elapsed):
            guard captureExists else { return }
            serviceEventContinuation.yield(.elapsed(elapsed))
            let warningTime = RecordingLimits.maximumDuration.timeInterval
                - RecordingLimits.warningLeadTime.timeInterval
            if elapsed >= warningTime, !warningEmitted {
                warningEmitted = true
                serviceEventContinuation.yield(.maximumDurationWarning)
            }
            if elapsed >= RecordingLimits.maximumDuration.timeInterval, !maximumStopRequested {
                maximumStopRequested = true
                Task { try? await self.stop() }
            }
        case .peakPower(let power):
            guard captureExists else { return }
            serviceEventContinuation.yield(.peakPower(power))
        case .routeChanged:
            guard captureExists else { return }
            serviceEventContinuation.yield(.routeChanged)
        case .interruption:
            guard captureExists else { return }
            if activating != nil {
                interruptionDuringActivation = true
            } else {
                Task { try? await self.handleInterruption() }
            }
        case .encoderCompleted(let duration, let peakPowerDBFS):
            guard captureExists else { return }
            guard encoderCompletion == nil, encoderFailure == nil else { return }
            let metrics = EncoderMetrics(duration: duration, peakPowerDBFS: peakPowerDBFS)
            encoderCompletion = metrics
            encoderWaiter?.resume(returning: metrics)
            encoderWaiter = nil
        case .failure:
            guard captureExists else { return }
            failEncoderWaiter(with: .encoderFailed)
        }
    }

    private func recorderEventsEnded() {
        recorderStreamEnded = true
        failEncoderWaiter(with: .eventStreamEnded)
    }

    private func failEncoderWaiter(with error: RecordingServiceError) {
        guard encoderCompletion == nil, encoderFailure == nil else { return }
        encoderFailure = error
        encoderWaiter?.resume(throwing: error)
        encoderWaiter = nil
    }

    private func waitForEncoderCompletion() async throws -> EncoderMetrics {
        if let encoderCompletion { return encoderCompletion }
        if let encoderFailure { throw encoderFailure }
        return try await withCheckedThrowingContinuation { encoderWaiter = $0 }
    }

    private func finalize(_ snapshot: RecordingSnapshot, outcome: CaptureOutcome) async throws -> Note? {
        if recorderStreamEnded { encoderFailure = .eventStreamEnded }
        do {
            if encoderCompletion == nil, encoderFailure == nil {
                try await recorder.stop()
            }
            let metrics = try await waitForEncoderCompletion()
            if metrics.duration < RecordingLimits.silenceDiscardDuration.timeInterval
                && metrics.peakPowerDBFS <= RecordingLimits.meaningfulPeakPowerDBFS {
                try files.deleteTemporary(sessionID: snapshot.sessionID)
                try await store.discardRecordingSession(sessionID: snapshot.sessionID)
                await activity?.end(sessionID: snapshot.sessionID)
                active = nil
                serviceEventContinuation.yield(.finalized(nil))
                return nil
            }
            let audio = try files.finalize(sessionID: snapshot.sessionID, noteID: snapshot.noteID)
            let finalized = FinalizedRecording(id: snapshot.noteID, recordingSessionID: snapshot.sessionID,
                title: timestampTitle(snapshot.createdAt), titleSource: .timestamp, createdAt: snapshot.createdAt,
                duration: audio.duration, source: snapshot.source, captureOutcome: outcome, requiresReview: false,
                audioURL: audio.url)
            let note = try await store.saveFinalized(finalized)
            await activity?.end(sessionID: snapshot.sessionID)
            active = nil
            serviceEventContinuation.yield(.finalized(note))
            return note
        } catch {
            await activity?.end(sessionID: snapshot.sessionID)
            active = nil
            let localError: LocalAudioError
            if let posix = error as? POSIXError, posix.code == .ENOSPC {
                localError = .storageFull
            } else if error is RecordingServiceError {
                localError = .unreadable
            } else {
                localError = .durabilityFailure
            }
            if error is RecordingServiceError { await recorder.discard() }
            try? await store.recordSessionError(localError, sessionID: snapshot.sessionID)
            serviceEventContinuation.yield(.finalizationFailed)
            throw error
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
