import Foundation
import AVFoundation
import XCTest
@testable import WhimCore

final class WebhookIntegrationTests: XCTestCase {
    // Break: request construction cannot distinguish missing/corrupt source audio from temp-output failures.
    func testBuilderReturnsTypedMissingAndUnreadableSourceErrors() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = StoredWebhookCredentials(endpoint: URL(string: "https://example.com/hook")!,
            bearerToken: nil, hmacSecret: nil, customHeaders: [])

        for (source, expected) in [
            (root.appendingPathComponent("missing.m4a"), WebhookRequestBuildError.sourceAudioMissing),
            (root, WebhookRequestBuildError.sourceAudioUnreadable),
        ] {
            let note = Note(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Audio error",
                titleSource: .timestamp, createdAt: Date(), duration: 1, source: .iphone,
                captureOutcome: .completed, requiresReview: false, audioURL: source)
            XCTAssertThrowsError(try WebhookRequestBuilder(temporaryDirectory: root).build(note: note,
                attemptID: AttemptID(), credentials: credentials, timestamp: 1_000,
                appVersion: "1", appBuild: "1")) { error in
                    XCTAssertEqual(error as? WebhookRequestBuildError, expected)
                }
        }
    }

    // Break: the bundled configuration test asset is absent, sensitive speech, or not playable AAC/M4A.
    func testBundledConfigurationAudioFixtureIsPlayableDeterministicTone() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "configuration-test-fixture", withExtension: "m4a",
            subdirectory: "Fixtures"))
        let audio = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(audio.length, 0)
        XCTAssertLessThan(Double(audio.length) / audio.fileFormat.sampleRate, 1)
    }
#if os(macOS)
    // Break: compiled app fixtures cannot induce a permanent failure at the validated /receive endpoint.
    func testLoopbackResponseControlChangesDeliveryAndResetRestoresSuccess() async throws {
        let server = try LoopbackServer()
        defer { server.stop() }
        var control = URLRequest(url: server.url(path: "/response"))
        control.httpMethod = "POST"
        control.setValue("application/json", forHTTPHeaderField: "Content-Type")
        control.httpBody = Data(#"{"status":400}"#.utf8)
        let (_, configured) = try await URLSession.shared.data(for: control)
        XCTAssertEqual((configured as? HTTPURLResponse)?.statusCode, 204)
        let failed = try await runDelivery(server: server, path: "/receive", responseTimeout: 2)
        XCTAssertEqual(failed.result, .failed)
        XCTAssertEqual(failed.note.delivery.failedAttempts.map(\.reason), [.httpStatus(400)])

        control.httpBody = Data(#"{"status":200}"#.utf8)
        let (_, restored) = try await URLSession.shared.data(for: control)
        XCTAssertEqual((restored as? HTTPURLResponse)?.statusCode, 204)
        let successful = try await runDelivery(server: server, path: "/receive", responseTimeout: 2)
        XCTAssertNotNil(successful.note.delivery.receipt)

        control.httpBody = Data(#"{"status":400}"#.utf8)
        _ = try await URLSession.shared.data(for: control)
        var reset = URLRequest(url: server.url(path: "/reset"))
        reset.httpMethod = "POST"
        let (_, resetResponse) = try await URLSession.shared.data(for: reset)
        XCTAssertEqual((resetResponse as? HTTPURLResponse)?.statusCode, 204)
        let afterReset = try await runDelivery(server: server, path: "/receive", responseTimeout: 2)
        XCTAssertNotNil(afterReset.note.delivery.receipt)
    }
    // Break: real HTTP responses are tested only at the transport seam, not through DeliveryService and SQLite.
    func testDeliveryServicePersistsRealLoopbackFailureMatrix() async throws {
        let server = try LoopbackServer()
        defer { server.stop() }
        let retryAt = Date(timeIntervalSince1970: 1_120)
        let cases: [(path: String, result: DeliveryResult, reason: AttemptFailureReason,
                     retryAfter: Date?, scheduled: Int, notifications: Int)] = [
            ("/drop", .scheduled(Date(timeIntervalSince1970: 1_060)), .network, nil, 1, 0),
            ("/receive?delay_ms=1000", .scheduled(Date(timeIntervalSince1970: 1_060)), .network, nil, 1, 0),
            ("/receive?status=408", .scheduled(Date(timeIntervalSince1970: 1_060)), .httpStatus(408), nil, 1, 0),
            ("/receive?status=425", .scheduled(Date(timeIntervalSince1970: 1_060)), .httpStatus(425), nil, 1, 0),
            ("/receive?status=429&retry_after=120", .scheduled(retryAt), .httpStatus(429), retryAt, 1, 0),
            ("/receive?status=400", .failed, .httpStatus(400), nil, 0, 1),
            ("/receive?status=500", .scheduled(Date(timeIntervalSince1970: 1_060)), .httpStatus(500), nil, 1, 0),
        ]

        for item in cases {
            let observed = try await runDelivery(server: server, path: item.path,
                responseTimeout: item.path.contains("delay_ms") ? 0.2 : 2)
            XCTAssertEqual(observed.result, item.result, item.path)
            XCTAssertEqual(observed.note.delivery.failedAttempts.map(\.reason), [item.reason], item.path)
            XCTAssertEqual(observed.note.delivery.failedAttempts.first?.retryAfter, item.retryAfter, item.path)
            XCTAssertEqual(observed.scheduledCount, item.scheduled, item.path)
            XCTAssertEqual(observed.notificationCount, item.notifications, item.path)
        }
    }

    // Break: releasing the lease after a known-outcome write failure lets another service resend the active Attempt.
    func testSeparateServiceDefersActiveAttemptAfterOutcomeWriteFailure() async throws {
        for statusCode in [204, 400] {
            let observed = try await runOutcomeWriteFailureIsolation(statusCode: statusCode)
            XCTAssertEqual(observed.secondResult, .scheduled(Date(timeIntervalSince1970: 1_135)),
                "HTTP \(statusCode)")
            XCTAssertEqual(observed.transportCount, 1, "HTTP \(statusCode)")
            XCTAssertEqual(observed.note.delivery.activeAttempts.count, 1, "HTTP \(statusCode)")
            XCTAssertTrue(observed.note.delivery.failedAttempts.isEmpty, "HTTP \(statusCode)")
            XCTAssertNil(observed.note.delivery.receipt, "HTTP \(statusCode)")
            XCTAssertFalse(observed.note.delivery.hasExecutionLease, "HTTP \(statusCode)")
            XCTAssertEqual(observed.scheduled, [Date(timeIntervalSince1970: 1_135)], "HTTP \(statusCode)")
        }
    }

    // Break: URLSession accepts a self-signed local certificate through a custom trust bypass.
    func testURLSessionRejectsSelfSignedTLSCertificate() async throws {
        let server = try LoopbackServer(useTLS: true)
        defer { server.stop() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audioURL = root.appendingPathComponent("tls.m4a")
        try Data("tls-audio".utf8).write(to: audioURL)
        let note = Note(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "TLS",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .iphone,
            captureOutcome: .completed, requiresReview: false, audioURL: audioURL)
        let credentials = StoredWebhookCredentials(endpoint: server.url(path: "/receive"), bearerToken: nil,
            hmacSecret: "receiver-secret", customHeaders: [])
        let request = try WebhookRequestBuilder(temporaryDirectory: root).build(note: note,
            attemptID: AttemptID(), credentials: credentials, timestamp: 1_000,
            appVersion: "1", appBuild: "1")
        defer { request.removeBodyFile() }

        do {
            _ = try await URLSessionHTTPTransport(requestTimeout: 1, resourceTimeout: 2).send(request)
            XCTFail("Expected normal TLS validation to reject the self-signed certificate")
        } catch let error as HTTPTransportError {
            XCTAssertEqual(error, .network)
        }
    }

    // Break: URLSession follows redirects, skips receiver verification, or retains an oversized response.
    func testLoopbackReceiverVerifiesContractRejectsRedirectsAndCapsBodies() async throws {
        let server = try LoopbackServer()
        defer { server.stop() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audioURL = root.appendingPathComponent("fixture.m4a")
        try Data("receiver-audio".utf8).write(to: audioURL)
        let note = Note(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Receiver test",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .iphone,
            captureOutcome: .completed, requiresReview: false, audioURL: audioURL)
        let attemptID = AttemptID()
        let credentials = StoredWebhookCredentials(endpoint: server.url(path: "/receive"), bearerToken: nil,
            hmacSecret: "receiver-secret", customHeaders: [])
        let builder = WebhookRequestBuilder(temporaryDirectory: root)
        let request = try builder.build(note: note, attemptID: attemptID, credentials: credentials,
            timestamp: 1_000, appVersion: "1", appBuild: "1", boundary: "integration-boundary")
        defer { request.removeBodyFile() }
        let response = try await URLSessionHTTPTransport().send(request)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.header("X-Whim-Note-ID"), note.id.rawValue.uuidString.lowercased())

        let redirectCredentials = StoredWebhookCredentials(endpoint: server.url(path: "/redirect"), bearerToken: nil,
            hmacSecret: "receiver-secret", customHeaders: [])
        let redirect = try builder.build(note: note, attemptID: AttemptID(), credentials: redirectCredentials,
            timestamp: 1_001, appVersion: "1", appBuild: "1")
        defer { redirect.removeBodyFile() }
        let redirectResponse = try await URLSessionHTTPTransport().send(redirect)
        XCTAssertEqual(redirectResponse.statusCode, 302)

        let oversizedCredentials = StoredWebhookCredentials(endpoint: server.url(path: "/oversized"), bearerToken: nil,
            hmacSecret: "receiver-secret", customHeaders: [])
        let oversized = try builder.build(note: note, attemptID: AttemptID(), credentials: oversizedCredentials,
            timestamp: 1_002, appVersion: "1", appBuild: "1")
        defer { oversized.removeBodyFile() }
        let capped = try await URLSessionHTTPTransport().send(oversized)
        XCTAssertEqual(capped.body.count, DeliveryTimeouts.maximumErrorExcerptBytes)
    }

    private func runDelivery(server: LoopbackServer, path: String, responseTimeout: TimeInterval) async throws
        -> (result: DeliveryResult, note: Note, scheduledCount: Int, notificationCount: Int) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audioURL = root.appendingPathComponent("delivery.m4a")
        try Data("pipeline-audio".utf8).write(to: audioURL)
        let clock = IntegrationClock(Date(timeIntervalSince1970: 1_000))
        let store = try SQLiteWhimStore.open(at: root.appendingPathComponent("whim.sqlite"), now: { clock.now })
        let revision = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: Date(timeIntervalSince1970: 900),
            endpoint: SanitizedEndpoint(url: server.url(path: path))!)
        try await store.saveConfigurationRevision(revision)
        let finalized = FinalizedRecording(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Pipeline",
            titleSource: .timestamp, createdAt: Date(timeIntervalSince1970: 900), duration: 1,
            source: .iphone, captureOutcome: .completed, requiresReview: false, audioURL: audioURL)
        _ = try await store.saveFinalized(finalized)
        let credentials = IntegrationCredentialStore(revisionID: revision.id,
            value: StoredWebhookCredentials(endpoint: server.url(path: path), bearerToken: nil,
                hmacSecret: "receiver-secret", customHeaders: []))
        let scheduler = IntegrationDeliveryScheduler()
        let notifications = IntegrationNotificationAdapter()
        let service = DeliveryService(store: store, credentials: credentials,
            transport: URLSessionHTTPTransport(requestTimeout: responseTimeout, resourceTimeout: responseTimeout),
            notifications: notifications, clock: clock, scheduler: scheduler, isConnected: { true },
            requestBuilder: WebhookRequestBuilder(temporaryDirectory: root), scheduledFailure: { _, _ in },
            appVersion: "1", appBuild: "1")

        let result = try await service.deliver(noteID: finalized.id)
        let stored = try await store.note(id: finalized.id)
        let note = try XCTUnwrap(stored)
        return (result, note, await scheduler.count, await notifications.count)
    }

    private func runOutcomeWriteFailureIsolation(statusCode: Int) async throws
        -> (secondResult: DeliveryResult, transportCount: Int, note: Note, scheduled: [Date]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audioURL = root.appendingPathComponent("delivery.m4a")
        try Data("isolated-audio".utf8).write(to: audioURL)
        let clock = IntegrationClock(Date(timeIntervalSince1970: 1_000))
        let databaseURL = root.appendingPathComponent("whim.sqlite")
        let firstDatabase = try SQLiteWhimStore.open(at: databaseURL, now: { clock.now })
        let secondDatabase = try SQLiteWhimStore.open(at: databaseURL, now: { clock.now })
        let revision = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: Date(timeIntervalSince1970: 900),
            endpoint: SanitizedEndpoint(scheme: "https", host: "example.com", path: "/hook"))
        try await firstDatabase.saveConfigurationRevision(revision)
        let finalized = FinalizedRecording(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Isolation",
            titleSource: .timestamp, createdAt: Date(timeIntervalSince1970: 900), duration: 1,
            source: .iphone, captureOutcome: .completed, requiresReview: false, audioURL: audioURL)
        _ = try await firstDatabase.saveFinalized(finalized)
        let credentials = IntegrationCredentialStore(revisionID: revision.id,
            value: StoredWebhookCredentials(endpoint: URL(string: "https://example.com/hook")!, bearerToken: nil,
                hmacSecret: nil, customHeaders: []))
        let transport = IntegrationHTTPTransport(statusCode: statusCode)
        let notifications = IntegrationNotificationAdapter()
        let firstScheduler = IntegrationDeliveryScheduler()
        let secondScheduler = IntegrationDeliveryScheduler()
        let failingStore = OutcomeWriteFailingStore(underlying: firstDatabase,
            outcome: statusCode == 204 ? .receipt : .attemptFailure)
        let first = DeliveryService(store: failingStore, credentials: credentials, transport: transport,
            notifications: notifications, clock: clock, scheduler: firstScheduler, isConnected: { true },
            requestBuilder: WebhookRequestBuilder(temporaryDirectory: root), scheduledFailure: { _, _ in },
            appVersion: "1", appBuild: "1")
        let second = DeliveryService(store: secondDatabase, credentials: credentials, transport: transport,
            notifications: notifications, clock: clock, scheduler: secondScheduler, isConnected: { true },
            requestBuilder: WebhookRequestBuilder(temporaryDirectory: root), scheduledFailure: { _, _ in },
            appVersion: "1", appBuild: "1")

        do {
            _ = try await first.deliver(noteID: finalized.id)
            XCTFail("Expected injected HTTP \(statusCode) outcome write failure")
        } catch is InjectedOutcomeWriteError {}
        let secondResult = try await second.deliver(noteID: finalized.id)
        let stored = try await secondDatabase.note(id: finalized.id)
        let note = try XCTUnwrap(stored)
        return (secondResult, await transport.count, note, await secondScheduler.earliestDates)
    }
#endif
    // Break: multipart order/media types, digests, signing, or idempotency headers drift from v1.
    func testBuilderProducesExactSignedMultipartContract() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audioURL = root.appendingPathComponent("audio.m4a")
        try Data("AUDIO-BYTES".utf8).write(to: audioURL)
        let noteID = NoteID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let attemptID = AttemptID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        let note = Note(id: noteID, recordingSessionID: RecordingSessionID(), title: "A title", titleSource: .timestamp,
            createdAt: Date(timeIntervalSince1970: 1_788_553_200), duration: 1.25, source: .iphone,
            captureOutcome: .completed, requiresReview: false, audioURL: audioURL)
        let credentials = StoredWebhookCredentials(endpoint: URL(string: "https://example.com/hook?q=actual")!,
            bearerToken: "bearer", hmacSecret: "hmac", customHeaders: [.init(name: "X-Custom", value: "custom")])

        let request = try WebhookRequestBuilder(temporaryDirectory: root).build(note: note, attemptID: attemptID,
            credentials: credentials, timestamp: 1_788_553_200, event: "note.created", appVersion: "1.0.0", appBuild: "1",
            boundary: "whim-boundary")
        defer { request.removeBodyFile() }

        XCTAssertEqual(request.url.absoluteString, "https://example.com/hook?q=actual")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["X-Whim-Note-ID"], noteID.rawValue.uuidString.lowercased())
        XCTAssertEqual(request.headers["X-Whim-Attempt-ID"], attemptID.rawValue.uuidString.lowercased())
        XCTAssertEqual(request.headers["Authorization"], "Bearer bearer")
        XCTAssertEqual(request.headers["X-Custom"], "custom")
        XCTAssertEqual(request.headers["X-Whim-Audio-SHA256"], "9c2e06637b8d660c2068fd84e98ae96f70d9df6286684f100ded8613e5a73d0a")
        XCTAssertTrue(request.headers["X-Whim-Signature"]!.hasPrefix("v1="))
        let body = try Data(contentsOf: request.bodyFileURL)
        let text = String(decoding: body, as: UTF8.self)
        let metadataRange = try XCTUnwrap(text.range(of: "name=\"metadata\""))
        let audioRange = try XCTUnwrap(text.range(of: "name=\"audio\""))
        XCTAssertLessThan(metadataRange.lowerBound, audioRange.lowerBound)
        XCTAssertTrue(text.contains("Content-Type: application/json\r\n\r\n{"))
        XCTAssertTrue(text.contains("Content-Type: audio/mp4\r\n\r\nAUDIO-BYTES\r\n--whim-boundary--\r\n"))
        XCTAssertEqual(Int64(body.count), request.contentLength)
    }
}

#if os(macOS)
private final class LoopbackServer {
    private let process = Process()
    private let port: Int
    private let scheme: String
    private let tlsDirectory: URL?

    init(useTLS: Bool = false) throws {
        let script = try XCTUnwrap(Bundle.module.url(forResource: "webhook-server", withExtension: "mjs",
            subdirectory: "Fixtures"))
        var additions = ["WHIM_WEBHOOK_PORT": "0", "WHIM_HMAC_SECRET": "receiver-secret"]
        if useTLS {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let key = directory.appendingPathComponent("key.pem")
            let certificate = directory.appendingPathComponent("certificate.pem")
            let openssl = Process()
            openssl.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            openssl.arguments = ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", key.path, "-out", certificate.path, "-subj", "/CN=127.0.0.1", "-days", "1"]
            openssl.standardOutput = FileHandle.nullDevice
            openssl.standardError = FileHandle.nullDevice
            try openssl.run()
            openssl.waitUntilExit()
            guard openssl.terminationStatus == 0 else { throw HTTPTransportError.invalidResponse }
            additions["WHIM_TLS_KEY_PATH"] = key.path
            additions["WHIM_TLS_CERT_PATH"] = certificate.path
            tlsDirectory = directory
            scheme = "https"
        } else {
            tlsDirectory = nil
            scheme = "http"
        }
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", script.path]
        process.environment = ProcessInfo.processInfo.environment.merging(additions) { _, new in new }
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.availableData
        guard let line = String(data: data, encoding: .utf8)?.split(separator: "\n").first,
              let json = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let port = json["port"] as? Int,
              json["tls"] as? Bool == useTLS else {
            process.terminate()
            throw HTTPTransportError.invalidResponse
        }
        self.port = port
    }

    func url(path: String) -> URL { URL(string: "\(scheme)://127.0.0.1:\(port)\(path)")! }
    func stop() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        if let tlsDirectory { try? FileManager.default.removeItem(at: tlsDirectory) }
    }
}

private final class IntegrationClock: Clock, @unchecked Sendable {
    private let value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { value }
}

private actor IntegrationCredentialStore: CredentialStore {
    private let revisionID: ConfigurationRevisionID
    private let value: StoredWebhookCredentials
    init(revisionID: ConfigurationRevisionID, value: StoredWebhookCredentials) {
        self.revisionID = revisionID
        self.value = value
    }
    func save(_ credentials: StoredWebhookCredentials, for revisionID: ConfigurationRevisionID) throws {}
    func credentials(for revisionID: ConfigurationRevisionID) -> StoredWebhookCredentials? {
        revisionID == self.revisionID ? value : nil
    }
    func remove(for revisionID: ConfigurationRevisionID) throws {}
    func removeAll() throws {}
}

private actor IntegrationDeliveryScheduler: DeliveryScheduler {
    private(set) var entries: [ScheduledDelivery] = []
    var count: Int { entries.count }
    var earliestDates: [Date] { entries.map(\.earliest) }
    func schedule(noteID: NoteID, earliest: Date,
                  operation: @escaping @Sendable () async throws -> Void,
                  onFailure: @escaping @Sendable (any Error) async -> Void) {
        entries.append(.init(noteID: noteID, earliest: earliest))
    }
    func cancel(noteID: NoteID) {}
}

private actor IntegrationNotificationAdapter: DeliveryNotificationAdapter {
    private(set) var count = 0
    func notifyFailure(title: String, reason: String, noteID: NoteID) { count += 1 }
}

private actor IntegrationHTTPTransport: HTTPTransport {
    private let statusCode: Int
    private(set) var count = 0
    init(statusCode: Int) { self.statusCode = statusCode }
    func send(_ request: WebhookRequest) -> HTTPResponse {
        count += 1
        return HTTPResponse(statusCode: statusCode)
    }
}

private enum InjectedOutcomeWriteError: Error { case write }

private actor OutcomeWriteFailingStore: WhimStore {
    enum Outcome { case receipt, attemptFailure }
    private let underlying: any WhimStore
    private let outcome: Outcome
    private var shouldFail = true

    init(underlying: any WhimStore, outcome: Outcome) {
        self.underlying = underlying
        self.outcome = outcome
    }

    func apply(_ event: DeliveryEvent, to noteID: NoteID) async throws -> Delivery {
        let matches = switch (outcome, event) {
        case (.receipt, .receipt), (.attemptFailure, .attemptFailed): true
        default: false
        }
        if matches, shouldFail {
            shouldFail = false
            throw InjectedOutcomeWriteError.write
        }
        return try await underlying.apply(event, to: noteID)
    }

    func recordLocalError(_ error: LocalAudioError, noteID: NoteID) async throws {
        try await underlying.recordLocalError(error, noteID: noteID)
    }
    func saveRecoveryError(_ recording: FinalizedRecording, error: LocalAudioError) async throws {
        try await underlying.saveRecoveryError(recording, error: error)
    }
    func send(noteID: NoteID) async throws { try await underlying.send(noteID: noteID) }
    func saveRecordingSession(_ session: RecordingSession) async throws {
        try await underlying.saveRecordingSession(session)
    }
    func recordingSessions() async throws -> [RecordingSession] { try await underlying.recordingSessions() }
    func discardRecordingSession(sessionID: RecordingSessionID) async throws {
        try await underlying.discardRecordingSession(sessionID: sessionID)
    }
    func recordSessionError(_ error: LocalAudioError, sessionID: RecordingSessionID) async throws {
        try await underlying.recordSessionError(error, sessionID: sessionID)
    }
    func delete(noteID: NoteID) async throws { try await underlying.delete(noteID: noteID) }
    func acknowledgeDeletion(noteID: NoteID, endpoint: AttemptDevice) async throws {
        try await underlying.acknowledgeDeletion(noteID: noteID, endpoint: endpoint)
    }
    func deletions() async throws -> [DeletionTombstone] { try await underlying.deletions() }
    func saveConfigurationRevision(_ revision: ConfigurationRevision) async throws {
        try await underlying.saveConfigurationRevision(revision)
    }
    func configurationRevision(for noteID: NoteID) async throws -> ConfigurationRevision? {
        try await underlying.configurationRevision(for: noteID)
    }
    func note(id: NoteID) async throws -> Note? { try await underlying.note(id: id) }
    func listNotes(filter: NoteFilter) async throws -> [NoteProjection] {
        try await underlying.listNotes(filter: filter)
    }
    func saveFinalized(_ finalized: FinalizedRecording) async throws -> Note {
        try await underlying.saveFinalized(finalized)
    }
    func updateTitle(noteID: NoteID, title: String, source: TitleSource) async throws {
        try await underlying.updateTitle(noteID: noteID, title: title, source: source)
    }
    func acquireLease(_ kind: LeaseKind, noteID: NoteID, owner: UUID, until: Date) async throws -> Bool {
        try await underlying.acquireLease(kind, noteID: noteID, owner: owner, until: until)
    }
    func releaseLease(_ kind: LeaseKind, noteID: NoteID, owner: UUID) async throws {
        try await underlying.releaseLease(kind, noteID: noteID, owner: owner)
    }
    func beginRetryCycle(noteID: NoteID) async throws -> Bool {
        try await underlying.beginRetryCycle(noteID: noteID)
    }
    func markExhaustionNotified(noteID: NoteID, retryCycle: Int) async throws -> Bool {
        try await underlying.markExhaustionNotified(noteID: noteID, retryCycle: retryCycle)
    }
}
#endif
