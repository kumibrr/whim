import Foundation
import XCTest
@testable import WhimCore

final class KeychainCredentialStoreIntegrationTests: XCTestCase {
    // Break: saving configuration does not update every unsent Note or return retry-offer counts.
    func testConfigurationSaveAppliesNewestRevisionAndReturnsOfferCounts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let serviceName = "app.whim.tests.\(UUID().uuidString)"
        let credentialStore = KeychainCredentialStore(service: serviceName)
        defer { Task { try? await credentialStore.removeAll() } }
        let store = try SQLiteWhimStore.open(at: root.appendingPathComponent("save.sqlite"))
        let awaiting = try await store.saveFinalized(fixtureRecording(root: root))
        let failed = try await store.saveFinalized(fixtureRecording(root: root))
        let oldRevision = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: Date(timeIntervalSince1970: 1),
            endpoint: SanitizedEndpoint(scheme: "https", host: "old.example.com", path: "/hook"))
        try await store.saveConfigurationRevision(oldRevision)
        let attempt = Attempt(noteID: failed.id, configurationRevisionID: oldRevision.id, device: .iphone,
            endpoint: oldRevision.endpoint, startedAt: Date())
        _ = try await store.apply(.attemptFailed(.init(attempt: attempt, failedAt: Date(), reason: .httpStatus(400))), to: failed.id)
        let service = WebhookConfigurationService(store: store, credentials: credentialStore)

        let counts = try await service.save(WebhookConfigurationInput(endpoint: "https://new.example.com/hook?key=secret"),
            now: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(counts.unsent, 2)
        XCTAssertEqual(counts.failed, 1)
        XCTAssertEqual(counts.awaitingSetup, 0)
        let selected = try await store.configurationRevision(for: awaiting.id)
        XCTAssertEqual(selected?.endpoint.host, "new.example.com")
    }

    // Break: credentials are unavailable after a new adapter instance or are copied into SQLite.
    func testCredentialsSurviveAdapterReopenWhileSQLiteContainsOnlySanitizedRevision() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("whim.sqlite")
        let service = "app.whim.tests.\(UUID().uuidString)"
        let credentials = KeychainCredentialStore(service: service)
        defer { Task { try? await credentials.removeAll() } }
        let store = try SQLiteWhimStore.open(at: databaseURL)
        let note = try await store.saveFinalized(fixtureRecording(root: root))
        let input = WebhookConfigurationInput(endpoint: "https://example.com/hook?token=QUERYSECRET",
            bearerToken: "BEARERSECRET", hmacSecret: "HMACSECRET",
            customHeaders: [.init(name: "X-Secret", value: "HEADERSECRET", isSecret: true)])
        let validated = try XCTUnwrap(WebhookValidator.validate(input).value)

        try await credentials.save(validated.credentials, for: validated.revision.id)
        try await store.saveConfigurationRevision(validated.revision)

        let reopened = KeychainCredentialStore(service: service)
        let loaded = try await reopened.credentials(for: validated.revision.id)
        XCTAssertEqual(loaded, validated.credentials)
        let revision = try await store.configurationRevision(for: note.id)
        XCTAssertEqual(revision?.endpoint.path, "/hook")
        let databaseFiles = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let bytes = try databaseFiles.reduce(into: Data()) { result, url in result.append(try Data(contentsOf: url)) }
        let databaseText = String(decoding: bytes, as: UTF8.self)
        for secret in ["QUERYSECRET", "BEARERSECRET", "HMACSECRET", "HEADERSECRET"] {
            XCTAssertFalse(databaseText.contains(secret))
        }
    }
}

private func fixtureRecording(root: URL) -> FinalizedRecording {
    FinalizedRecording(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Fixture",
        titleSource: .timestamp, createdAt: Date(), duration: 1, source: .iphone,
        captureOutcome: .completed, requiresReview: false, audioURL: root.appendingPathComponent("fixture.m4a"))
}
