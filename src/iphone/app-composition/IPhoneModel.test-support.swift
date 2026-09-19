import AVFoundation
import Foundation
import XCTest
import GRDB
@testable import WhimCore
final class WhimFacadeHarness: @unchecked Sendable {
    let root: URL
    let store: SQLiteWhimStore
    let files: AudioFileStore
    let recorder = FacadeRecorder()
    let credentials = FacadeCredentials()
    let transport: FacadeTransport
    let scheduler = FacadeScheduler()
    let clock: FacadeClock
    let preferences = FacadePreferences()
    let configuration: WebhookConfigurationService

    var databaseURL: URL { root.appendingPathComponent("whim.sqlite") }

    init(responses: [HTTPResponse] = [HTTPResponse(statusCode: 204)], root existingRoot: URL? = nil) throws {
        let clock = FacadeClock(Date(timeIntervalSince1970: 1_000))
        self.clock = clock
        root = existingRoot ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = try SQLiteWhimStore.open(at: root.appendingPathComponent("whim.sqlite"), now: { clock.now })
        files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        transport = FacadeTransport(responses: responses)
        configuration = WebhookConfigurationService(store: store, credentials: credentials)
    }

    func makeService(transcriber: any Transcriber = EmptyFacadeTranscriber(),
                     isConnected: @escaping @Sendable () async -> Bool = { true },
                     playback: any PlaybackAdapter = SystemPlaybackAdapter(),
                     permissions: any PermissionAdapter = SystemPermissionAdapter(),
                     preferences: (any PreferenceStoring)? = nil,
                     store selectedStore: (any WhimStore)? = nil,
                     requestBuilder: WebhookRequestBuilder = WebhookRequestBuilder(),
                     peer: ConnectivityMergeService? = nil,
                     onboarding: any OnboardingStoring = TestOnboarding()) -> WhimService {
        let selectedStore = selectedStore ?? store
        let title = TitleService(transcriber: transcriber, store: selectedStore)
        let delivery = DeliveryService(store: selectedStore, credentials: credentials, transport: transport,
            notifications: FacadeNotifications(), clock: clock, scheduler: scheduler, isConnected: isConnected,
            requestBuilder: requestBuilder,
            titleSnapshot: { await title.enrich($0) }, scheduledFailure: { _, _ in },
            appVersion: "1.0.0", appBuild: "1")
        let recording = RecordingService(recorder: recorder, store: selectedStore, files: files)
        let configurationTest = ConfigurationTestService(credentials: credentials, transport: transport,
            fixtureAudioURL: root.appendingPathComponent("test.m4a"), appVersion: "1.0.0", appBuild: "1")
        return WhimService(recording: recording, store: selectedStore, files: files, title: title,
            delivery: delivery, configuration: configuration, configurationTest: configurationTest,
            recovery: RecoveryScanner(store: selectedStore, files: files), preferences: preferences ?? self.preferences,
            credentials: credentials, scheduler: scheduler, onboarding: onboarding, permissions: permissions, playback: playback, peer: peer)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

actor DeniedFacadePermissions: PermissionAdapter {
    private(set) var requests = 0
    func status(_ kind: PermissionKind) -> PermissionStatus { .denied }
    func request(_ kind: PermissionKind) -> PermissionStatus { requests += 1; return .denied }
    func openSettings() {}
}

actor FacadeConnectivity {
    private(set) var value = false
    var readOccurred = false
    var readers: [CheckedContinuation<Void, Never>] = []
    func read() -> Bool {
        readOccurred = true
        readers.forEach { $0.resume() }; readers.removeAll()
        return value
    }
    func waitUntilRead() async {
        if readOccurred { return }
        await withCheckedContinuation { readers.append($0) }
    }
    func connect() { value = true }
}

actor FacadePlayback: PlaybackAdapter {
    var value: PlaybackProjection?
    func play(noteID: NoteID, url: URL) -> PlaybackProjection {
        let next = PlaybackProjection(noteID: noteID, isPlaying: true, elapsedSeconds: 0, durationSeconds: 2)
        value = next; return next
    }
    func stop() { value = nil }
    func snapshot() -> PlaybackProjection? { value }
}

actor FacadeRecorder: AudioRecorder {
    let pair = AsyncStream.makeStream(of: RecordingEvent.self)
    private(set) var startCount = 0
    func events() -> AsyncStream<RecordingEvent> { pair.stream }
    func start(at url: URL) throws { startCount += 1; try writeAudioFixture(to: url) }
    func stop() { pair.continuation.yield(.encoderCompleted(duration: 1, peakPowerDBFS: -10)) }
    func discard() {}
    func emit(_ event: RecordingEvent) { pair.continuation.yield(event) }
}

struct EmptyFacadeTranscriber: Transcriber {
    func transcribe(audioAt url: URL, locale: Locale) async throws -> String { "" }
}

final class BlockingFacadeTranscriber: Transcriber, @unchecked Sendable {
    let lock = NSLock()
    var continuation: CheckedContinuation<String, Error>?
    var terminal: Result<String, Error>?
    var waiters: [CheckedContinuation<Void, Never>] = []
    var calls = 0
    var callCount: Int { lock.withLock { calls } }
    func transcribe(audioAt url: URL, locale: Locale) async throws -> String {
        lock.withLock { calls += 1; waiters.forEach { $0.resume() }; waiters.removeAll() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let terminal = lock.withLock { () -> Result<String, Error>? in
                    if let terminal { return terminal }
                    self.continuation = continuation
                    return nil
                }
                if let terminal { continuation.resume(with: terminal) }
            }
        } onCancel: {
            self.resolve(.failure(CancellationError()))
        }
    }
    func waitUntilStarted() async {
        await withCheckedContinuation { waiter in
            let alreadyStarted = lock.withLock { () -> Bool in
                guard calls == 0 else { return true }
                waiters.append(waiter)
                return false
            }
            if alreadyStarted { waiter.resume() }
        }
    }
    func finish(with value: String) { resolve(.success(value)) }
    func resolve(_ value: Result<String, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<String, Error>? in
            guard terminal == nil else { return nil }
            terminal = value
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(with: value)
    }
}

actor FacadeCredentials: CredentialStore {
    var values: [ConfigurationRevisionID: StoredWebhookCredentials] = [:]
    func save(_ credentials: StoredWebhookCredentials, for revisionID: ConfigurationRevisionID) { values[revisionID] = credentials }
    func credentials(for revisionID: ConfigurationRevisionID) -> StoredWebhookCredentials? { values[revisionID] }
    func remove(for revisionID: ConfigurationRevisionID) { values[revisionID] = nil }
    func removeAll() { values.removeAll() }
    var count: Int { values.count }
}

actor FacadeTransport: HTTPTransport {
    private(set) var requestCount = 0
    private(set) var cancellationCount = 0
    var responses: [HTTPResponse]
    var suspended = false
    var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    init(responses: [HTTPResponse]) { self.responses = responses }
    func send(_ request: WebhookRequest) async throws -> HTTPResponse {
        requestCount += 1
        let ready = waiters.filter { requestCount >= $0.0 }
        waiters.removeAll { requestCount >= $0.0 }
        ready.forEach { $0.1.resume() }
        while suspended {
            do { try await Task.sleep(for: .milliseconds(5)) }
            catch { cancellationCount += 1; throw error }
        }
        return responses.isEmpty ? HTTPResponse(statusCode: 204) : responses.removeFirst()
    }
    func waitForRequestCount(_ count: Int) async {
        if requestCount >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func suspendResponses() { suspended = true }
    func resumeResponses() { suspended = false }
}

actor FacadeScheduler: DeliveryScheduler {
    typealias Operation = @Sendable () async throws -> Void
    var operations: [Operation] = []
    var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func schedule(noteID: NoteID, earliest: Date,
        operation: @escaping @Sendable () async throws -> Void,
        onFailure: @escaping @Sendable (any Error) async -> Void) {
        operations.append(operation)
        let ready = waiters.filter { operations.count >= $0.0 }
        waiters.removeAll { operations.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
    func cancel(noteID: NoteID) { operations.removeAll() }
    func waitForCount(_ count: Int) async {
        if operations.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func runNext() async throws { try await operations.removeFirst()() }
}

final class FacadeClock: Clock, @unchecked Sendable {
    let lock = NSLock()
    var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.withLock { value } }
    func advance(by interval: TimeInterval) { lock.withLock { value.addTimeInterval(interval) } }
}

final class FacadeEventProbe: @unchecked Sendable {
    let lock = NSLock()
    var statuses: [DeliveryStatus] = []
    var workflowErrors: [DeliveryWorkflowError] = []
    var statusWaiters: [(DeliveryStatus, Int, CheckedContinuation<Void, Never>)] = []
    var errorWaiters: [(DeliveryWorkflowError, CheckedContinuation<Void, Never>)] = []
    var task: Task<Void, Never>?

    init(stream: AsyncStream<WhimEvent>) {
        task = Task { [weak self] in
            for await event in stream {
                guard let note = event.note else { continue }
                self?.record(status: note.status, workflowError: note.workflowError)
            }
        }
    }

    deinit { task?.cancel() }

    func waitForStatus(_ status: DeliveryStatus, count: Int) async {
        await withCheckedContinuation { continuation in
            let alreadyObserved = lock.withLock { () -> Bool in
                guard statuses.count(where: { $0 == status }) < count else { return true }
                statusWaiters.append((status, count, continuation))
                return false
            }
            if alreadyObserved { continuation.resume() }
        }
    }

    func waitForWorkflowError(_ error: DeliveryWorkflowError) async {
        await withCheckedContinuation { continuation in
            let alreadyObserved = lock.withLock { () -> Bool in
                guard !workflowErrors.contains(error) else { return true }
                errorWaiters.append((error, continuation))
                return false
            }
            if alreadyObserved { continuation.resume() }
        }
    }

    func record(status: DeliveryStatus, workflowError: DeliveryWorkflowError?) {
        let ready = lock.withLock { () -> ([CheckedContinuation<Void, Never>], [CheckedContinuation<Void, Never>]) in
            statuses.append(status)
            if let workflowError { workflowErrors.append(workflowError) }
            let readyStatuses = statusWaiters.filter { waiter in
                statuses.count(where: { value in value == waiter.0 }) >= waiter.1
            }
            statusWaiters.removeAll { waiter in
                statuses.count(where: { $0 == waiter.0 }) >= waiter.1
            }
            let readyErrors = errorWaiters.filter { workflowErrors.contains($0.0) }
            errorWaiters.removeAll { workflowErrors.contains($0.0) }
            return (readyStatuses.map(\.2), readyErrors.map(\.1))
        }
        (ready.0 + ready.1).forEach { $0.resume() }
    }
}

struct FacadeNotifications: DeliveryNotificationAdapter {
    func notifyFailure(title: String, reason: String, noteID: NoteID) async {}
}

actor FacadePreferences: PreferenceStoring {
    var value = PreferenceInput.default
    func load() -> PreferenceInput { value }
    func save(_ input: PreferenceInput) { value = input }
    func reset() { value = .default }
}

actor BlockingFacadePreferences: PreferenceStoring {
    var saveContinuation: CheckedContinuation<Void, Never>?
    var waiters: [CheckedContinuation<Void, Never>] = []
    func load() -> PreferenceInput { .default }
    func save(_ input: PreferenceInput) async {
        waiters.forEach { $0.resume() }; waiters.removeAll()
        await withCheckedContinuation { saveContinuation = $0 }
    }
    func reset() {}
    func waitUntilSaving() async {
        if saveContinuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func finishSaving() { saveContinuation?.resume(); saveContinuation = nil }
}

actor TestOnboarding: OnboardingStoring {
    var completed = false
    func isComplete() -> Bool { completed }
    func complete() { completed = true }
    func reset() { completed = false }
}

func writeAudioFixture(to url: URL) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let writer = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
    ])
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
    buffer.frameLength = 1_600
    buffer.floatChannelData![0].initialize(repeating: 0, count: 1_600)
    try writer.write(from: buffer)
}

actor GatedPlayback: PlaybackAdapter {
    private var remaining = 0
    private var calls = 0
    private var held: [Int: CheckedContinuation<Void, Never>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func arm(_ count: Int = 1) { remaining = count; calls = 0 }
    func play(noteID: NoteID, url: URL) -> PlaybackProjection { .init(noteID: noteID, isPlaying: true, elapsedSeconds: 0, durationSeconds: 10) }
    func stop() {}
    func snapshot() async -> PlaybackProjection? {
        if remaining > 0 {
            remaining -= 1; calls += 1
            let call = calls
            await withCheckedContinuation { continuation in
                held[call] = continuation
                let ready = waiters.filter { $0.0 == call }
                waiters.removeAll { $0.0 == call }
                ready.forEach { $0.1.resume() }
            }
        }
        return nil
    }
    func waitForSnapshot(_ call: Int) async {
        if held[call] != nil { return }
        await withCheckedContinuation { waiters.append((call, $0)) }
    }
    func release(_ call: Int) { held.removeValue(forKey: call)?.resume() }
}

func relocateLegacyAudio(root: URL) throws {
    let queue = try DatabaseQueue(path: root.appendingPathComponent("whim.sqlite").path)
    try queue.write { db in
        for row in try Row.fetchAll(db, sql: "SELECT id, metadata FROM notes") {
            let id: String = row["id"]
            let metadata: Data = row["metadata"]
            var object = try JSONSerialization.jsonObject(with: metadata) as! [String: Any]
            object["audioURL"] = root.appendingPathComponent("Audio/Notes/\(id).m4a").absoluteString
            try db.execute(sql: "UPDATE notes SET metadata = ? WHERE id = ?", arguments: [try JSONSerialization.data(withJSONObject: object), id])
        }
    }
}
actor MutablePermissions: PermissionAdapter {
    private var permission = PermissionStatus.denied
    func grant() { permission = .granted }
    func status(_ kind: PermissionKind) -> PermissionStatus { permission }
    func request(_ kind: PermissionKind) -> PermissionStatus { permission }
    func openSettings() {}
}
