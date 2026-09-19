import XCTest
import AVFoundation
import GRDB
import WhimCore
@testable import WhimWatch

@MainActor
final class WatchModelIntegrationTests: XCTestCase {
    func testRecordingPowerEventsDriveTheLiveWaveformAndStopResetsIt() async throws {
        let fixture = try WatchFixture()
        defer { fixture.remove() }
        let model = WatchModel(client: fixture.client, haptic: { _ in })
        await model.activate()

        await fixture.microphone.emit(.peakPower(-18))
        for _ in 0..<100 {
            if model.peakPowerDBFS == -18 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.peakPowerDBFS, -18)

        await model.stop()
        XCTAssertEqual(model.peakPowerDBFS, -160)
    }

    func testLaunchAndWristDownRestoreOneRecordingSession() async throws {
        let fixture = try WatchFixture()
        defer { fixture.remove() }
        let model = WatchModel(client: fixture.client, haptic: { _ in })
        await model.activate()
        let initial = try await fixture.client.activeRecording()
        XCTAssertEqual(initial?.source, .appleWatch)
        await model.activate()
        let restored = try await fixture.client.activeRecording()
        XCTAssertEqual(restored?.sessionID, initial?.sessionID)
        await model.discard()
    }
    func testMissingPermissionCreatesNoRecordingSession() async throws {
        let fixture = try WatchFixture(permission: .denied)
        defer { fixture.remove() }
        let model = WatchModel(client: fixture.client, haptic: { _ in })
        await model.activate()
        let session = try await fixture.client.activeRecording()
        XCTAssertNil(session)
        let notes = try await fixture.client.listNotes(filter: .all)
        XCTAssertTrue(notes.isEmpty)
    }

    func testStopPreservesTimestampNoteAndDoesNotRestartOnReactivation() async throws {
        let fixture = try WatchFixture()
        defer { fixture.remove() }
        let model = WatchModel(client: fixture.client, haptic: { _ in })
        await model.activate()
        await model.stop()
        await model.activate()
        let notes = try await fixture.client.listNotes(filter: .all)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "Sep 4, 2026 at 10:00")
        XCTAssertEqual(notes.first?.status, .setupRequired)
        XCTAssertEqual(notes.first?.source, .appleWatch)
        let session = try await fixture.client.activeRecording()
        XCTAssertNil(session)
    }

    func testDiscardCreatesNoNoteAndExplicitRecordStartsAgain() async throws {
        let fixture = try WatchFixture()
        defer { fixture.remove() }
        let model = WatchModel(client: fixture.client, haptic: { _ in })
        await model.activate()
        await model.discard()
        let notes = try await fixture.client.listNotes(filter: .all)
        XCTAssertTrue(notes.isEmpty)
        await model.record()
        let session = try await fixture.client.activeRecording()
        XCTAssertNotNil(session)
        await model.discard()
    }

    func testInterruptedRecordingIsPreservedWithoutImplicitMicrophoneResume() async throws {
        let fixture = try WatchFixture()
        defer { fixture.remove() }
        let model = WatchModel(client: fixture.client, haptic: { _ in })
        await model.activate()
        await fixture.microphone.emit(.interruption)
        try await waitForNote(fixture.client)
        await model.activate()
        let session = try await fixture.client.activeRecording()
        XCTAssertNil(session)
        let notes = try await fixture.client.listNotes(filter: .all)
        XCTAssertEqual(notes.count, 1)
    }

    func testFiveMinuteLimitFinalizesOneNote() async throws {
        let fixture = try WatchFixture()
        defer { fixture.remove() }
        let model = WatchModel(client: fixture.client, haptic: { _ in })
        await model.activate()
        await fixture.microphone.emit(.elapsed(300))
        try await waitForNote(fixture.client)
        let session = try await fixture.client.activeRecording()
        XCTAssertNil(session)
        let notes = try await fixture.client.listNotes(filter: .all)
        XCTAssertEqual(notes.count, 1)
    }

    func testConfiguredOfflineWatchQueuesWithoutConsumingAnAttempt() async throws {
        let fixture = try WatchFixture()
        defer { fixture.remove() }
        _ = try await fixture.client.updateWebhook(.init(endpoint: "https://example.com/receive"))
        let model = WatchModel(client: fixture.client, haptic: { _ in })
        await model.activate()
        await model.stop()
        let notes = try await fixture.client.listNotes(filter: .all)
        let note = try XCTUnwrap(notes.first)
        XCTAssertEqual(note.status, .queued)
        let detail = try await fixture.client.note(id: note.id)
        XCTAssertEqual(detail?.attempts.count, 0)
    }

    func testConfiguredOnlineWatchDeliversDirectlyWithWatchAttempt() async throws {
        let fixture = try WatchFixture(connected: true)
        defer { fixture.remove() }
        _ = try await fixture.client.updateWebhook(.init(endpoint: "https://example.com/receive"))
        let model = WatchModel(client: fixture.client, haptic: { _ in })
        await model.activate()
        await model.stop()
        for _ in 0..<100 {
            if try await fixture.client.listNotes(filter: .sent).count == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let notes = try await fixture.client.listNotes(filter: .sent)
        let note = try XCTUnwrap(notes.first)
        let detail = try await fixture.client.note(id: note.id)
        XCTAssertEqual(detail?.attempts.first?.device, .appleWatch)
    }

    func testPendingRetryCannotBlockStopOrSkipDeletion() async throws {
        for deleting in [false, true] {
            let fixture = try WatchFixture(connected: true)
            defer { fixture.remove() }
            await fixture.transport.setResponses([400, 204])
            _ = try await fixture.client.updateWebhook(.init(endpoint: "https://example.com/receive"))
            let model = WatchModel(client: fixture.client, haptic: { _ in })
            await model.activate()
            await model.stop()
            let old = try await failedNote(fixture.client)
            await model.record()
            await fixture.transport.suspend()
            let retry = Task { await model.retry(old) }
            try await fixture.transport.waitForRequests(2)
            let completed = expectation(description: "User command completes before retry response")
            let command = Task {
                if deleting { await model.delete(old) } else { await model.stop() }
                completed.fulfill()
            }
            await fulfillment(of: [completed], timeout: 1)
            await fixture.transport.resume()
            await retry.value
            await command.value
            if deleting {
                let remaining = try await fixture.client.note(id: old.id)
                XCTAssertNil(remaining, "Delete must execute while Retry is pending")
                await model.discard()
            } else {
                let active = try await fixture.client.activeRecording()
                XCTAssertNil(active, "Stop must not be dropped while Retry is pending")
            }
        }
    }

    func testEventRefreshFailureIsVisibleAndLaterEventClearsIt() async throws {
        let fixture = try WatchFixture(connected: true)
        defer { fixture.remove() }
        _ = try await fixture.client.updateWebhook(.init(endpoint: "https://example.com/receive"))
        await fixture.transport.suspend()
        let model = WatchModel(client: fixture.client, haptic: { _ in })
        await model.activate()
        await model.stop()
        try await fixture.transport.waitForRequests(1)
        let database = try DatabaseQueue(path: fixture.root.appendingPathComponent("whim.sqlite").path)
        defer { try? database.close() }
        // Fixture-only schema fault breaks the timeline query while Note-by-ID delivery
        // writes still succeed, so the real delivery event exercises the failing refresh.
        try await database.write { try $0.execute(sql: "ALTER TABLE notes RENAME COLUMN created_at TO unavailable_created_at") }
        await fixture.transport.resume()
        for _ in 0..<100 {
            if model.error != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.error, "Recent Notes could not be refreshed. Try again.")
        try await database.write { try $0.execute(sql: "ALTER TABLE notes RENAME COLUMN unavailable_created_at TO created_at") }
        _ = try await fixture.client.startRecording(source: .appleWatch)
        _ = try await fixture.client.stopRecording()
        for _ in 0..<100 {
            if model.notes.count == 2, model.error == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(model.error)
        XCTAssertEqual(model.notes.count, 2)
    }

    private func failedNote(_ client: WhimService) async throws -> NoteProjection {
        for _ in 0..<100 {
            if let note = try await client.listNotes(filter: .failed).first { return note }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw WhimServiceError.setupRequired("Fixture did not produce a failed Note")
    }

    private func waitForNote(_ client: WhimService) async throws {
        for _ in 0..<100 {
            if try await !client.listNotes(filter: .all).isEmpty { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Finalization did not produce a Note")
    }

}

private final class WatchFixture {
    let root: URL
    let client: WhimService
    let microphone: WatchMicrophone
    let transport = WatchTransport()
    init(permission: PermissionStatus = .granted, connected: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try SQLiteWhimStore.open(at: root.appendingPathComponent("whim.sqlite"))
        let files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        microphone = WatchMicrophone()
        let recording = RecordingService(recorder: microphone, store: store, files: files,
            now: { Date(timeIntervalSince1970: 1_000) }, timestampTitle: { _ in "Sep 4, 2026 at 10:00" })
        let title = TitleService(transcriber: WatchNoTranscription(), store: store)
        let credentials = WatchCredentials()
        let scheduler = InProcessDeliveryScheduler()
        let delivery = DeliveryService(store: store, credentials: credentials, transport: transport,
            notifications: WatchNotifications(), scheduler: scheduler, isConnected: { connected },
            scheduledFailure: { _, _ in }, device: .appleWatch, appVersion: "1", appBuild: "1")
        client = WhimService(recording: recording, store: store, files: files, title: title,
            delivery: delivery, configuration: WebhookConfigurationService(store: store, credentials: credentials),
            configurationTest: ConfigurationTestService(credentials: credentials, transport: transport,
                fixtureAudioURL: root.appendingPathComponent("fixture.m4a"), appVersion: "1", appBuild: "1"),
            recovery: RecoveryScanner(store: store, files: files),
            preferences: try UserDefaultsPreferenceStore(suiteName: "watch-test-\(UUID())"),
            credentials: credentials, scheduler: scheduler, permissions: WatchPermissions(value: permission))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
private actor WatchMicrophone: AudioRecorder {
    let pair = AsyncStream.makeStream(of: RecordingEvent.self)
    func events() -> AsyncStream<RecordingEvent> { pair.stream }
    func start(at url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let writer = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
        ])
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000)!
        buffer.frameLength = 32_000
        buffer.floatChannelData![0].initialize(repeating: 0.1, count: 32_000)
        try writer.write(from: buffer)
    }
    func stop() { pair.continuation.yield(.encoderCompleted(duration: 2, peakPowerDBFS: -12)) }
    func discard() {}
    func emit(_ event: RecordingEvent) { pair.continuation.yield(event) }
}
private struct WatchNoTranscription: Transcriber {
    func transcribe(audioAt url: URL, locale: Locale) throws -> String { throw TranscriptionError.unavailable }
}
private actor WatchCredentials: CredentialStore {
    var values: [ConfigurationRevisionID: StoredWebhookCredentials] = [:]
    func save(_ credentials: StoredWebhookCredentials, for revisionID: ConfigurationRevisionID) { values[revisionID] = credentials }
    func credentials(for revisionID: ConfigurationRevisionID) -> StoredWebhookCredentials? { values[revisionID] }
    func remove(for revisionID: ConfigurationRevisionID) { values[revisionID] = nil }
    func removeAll() { values.removeAll() }
}
private actor WatchTransport: HTTPTransport {
    private var responses: [Int] = []
    private var suspended = false
    private var requests = 0
    func send(_ request: WebhookRequest) async throws -> HTTPResponse {
        requests += 1
        while suspended { try await Task.sleep(for: .milliseconds(5)) }
        return .init(statusCode: responses.isEmpty ? 204 : responses.removeFirst())
    }
    func setResponses(_ responses: [Int]) { self.responses = responses }
    func suspend() { suspended = true }
    func resume() { suspended = false }
    func waitForRequests(_ count: Int) async throws {
        for _ in 0..<200 {
            if requests >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw WhimServiceError.setupRequired("Fixture HTTP request did not start")
    }
}
private struct WatchNotifications: DeliveryNotificationAdapter {
    func notifyFailure(title: String, reason: String, noteID: NoteID) async {}
}
private struct WatchPermissions: PermissionAdapter {
    let value: PermissionStatus
    func status(_ kind: PermissionKind) async -> PermissionStatus { value }
    func request(_ kind: PermissionKind) async -> PermissionStatus { value }
    func openSettings() async {}
}
