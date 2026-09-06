import Foundation
import XCTest
@testable import WhimCore

final class ConfigurationTestServiceTests: XCTestCase {
    // Break: configuration tests consume Note state, reuse IDs, emit note.created, or require acknowledgement to pass.
    func testSendsFreshConfigurationTestAndReportsOptionalIdempotencyConfirmation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = root.appendingPathComponent("fixture.m4a")
        try Data("fixture".utf8).write(to: fixture)
        let revision = ConfigurationRevisionID()
        let credentialStore = ConfigurationCredentialFake(revision: revision,
            credentials: .init(endpoint: URL(string: "https://example.com/test")!, bearerToken: nil,
                hmacSecret: nil, customHeaders: []))
        let transport = ConfigurationCaptureTransport()
        let service = ConfigurationTestService(credentials: credentialStore, transport: transport,
            fixtureAudioURL: fixture, clock: MutableConfigurationClock(), appVersion: "1", appBuild: "1")

        let first = try await service.send(revisionID: revision)
        let second = try await service.send(revisionID: revision)
        let captures = await transport.captures

        XCTAssertTrue(first.passed)
        XCTAssertFalse(first.idempotencyConfirmed)
        XCTAssertTrue(second.idempotencyConfirmed)
        XCTAssertEqual(captures.count, 2)
        XCTAssertNotEqual(captures[0].noteID, captures[1].noteID)
        XCTAssertNotEqual(captures[0].attemptID, captures[1].attemptID)
        XCTAssertTrue(captures.allSatisfy { $0.event == "configuration.test" })
    }
}

private struct ConfigurationCapture: Sendable {
    let noteID: String
    let attemptID: String
    let event: String
}

private actor ConfigurationCaptureTransport: HTTPTransport {
    private(set) var captures: [ConfigurationCapture] = []
    func send(_ request: WebhookRequest) throws -> HTTPResponse {
        let body = try Data(contentsOf: request.bodyFileURL)
        let text = String(decoding: body, as: UTF8.self)
        let event = text.contains(#""event":"configuration.test""#) ? "configuration.test" : "wrong"
        let noteID = request.headers["X-Whim-Note-ID"]!
        let attemptID = request.headers["X-Whim-Attempt-ID"]!
        captures.append(.init(noteID: noteID, attemptID: attemptID, event: event))
        if captures.count == 1 { return HTTPResponse(statusCode: 204) }
        return HTTPResponse(statusCode: 200, body: Data(#"{"note_id":"\#(noteID)"}"#.utf8))
    }
}

private struct MutableConfigurationClock: Clock {
    let now = Date(timeIntervalSince1970: 1_000)
}

private actor ConfigurationCredentialFake: CredentialStore {
    let revision: ConfigurationRevisionID
    let value: StoredWebhookCredentials
    init(revision: ConfigurationRevisionID, credentials: StoredWebhookCredentials) { self.revision = revision; value = credentials }
    func save(_ credentials: StoredWebhookCredentials, for revisionID: ConfigurationRevisionID) throws {}
    func credentials(for revisionID: ConfigurationRevisionID) -> StoredWebhookCredentials? { revisionID == revision ? value : nil }
    func remove(for revisionID: ConfigurationRevisionID) throws {}
    func removeAll() throws {}
}
