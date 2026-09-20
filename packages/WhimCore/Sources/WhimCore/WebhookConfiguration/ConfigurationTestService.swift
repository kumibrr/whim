import Foundation

public struct ConfigurationTestResult: Codable, Equatable, Sendable {
    public let passed: Bool
    public let statusCode: Int?
    public let idempotencyConfirmed: Bool

    public init(passed: Bool, statusCode: Int?, idempotencyConfirmed: Bool) {
        self.passed = passed
        self.statusCode = statusCode
        self.idempotencyConfirmed = idempotencyConfirmed
    }
    private enum CodingKeys: String, CodingKey { case passed, statusCode, idempotencyConfirmed }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(passed, forKey: .passed); try values.encode(statusCode, forKey: .statusCode)
        try values.encode(idempotencyConfirmed, forKey: .idempotencyConfirmed)
    }
}

public enum ConfigurationTestError: Error, CustomStringConvertible {
    case missingConfiguration

    public var description: String { "No usable webhook configuration is available." }
}

public struct ConfigurationTestService: Sendable {
    private let credentialStore: any CredentialStore
    private let transport: any HTTPTransport
    private let fixtureAudioURL: @Sendable () throws -> URL
    private let clock: any Clock
    private let requestBuilder: WebhookRequestBuilder
    private let appVersion: String
    private let appBuild: String

    public init(credentials: any CredentialStore, transport: any HTTPTransport,
                fixtureAudio: @escaping @Sendable () throws -> URL, clock: any Clock = SystemClock(),
                requestBuilder: WebhookRequestBuilder = WebhookRequestBuilder(),
                appVersion: String, appBuild: String) {
        self.credentialStore = credentials
        self.transport = transport
        self.fixtureAudioURL = fixtureAudio
        self.clock = clock
        self.requestBuilder = requestBuilder
        self.appVersion = appVersion
        self.appBuild = appBuild
    }

    public init(credentials: any CredentialStore, transport: any HTTPTransport,
                fixtureAudioURL: URL, clock: any Clock = SystemClock(),
                requestBuilder: WebhookRequestBuilder = WebhookRequestBuilder(),
                appVersion: String, appBuild: String) {
        self.init(credentials: credentials, transport: transport, fixtureAudio: { fixtureAudioURL },
            clock: clock, requestBuilder: requestBuilder, appVersion: appVersion, appBuild: appBuild)
    }

    public func send(revisionID: ConfigurationRevisionID) async throws -> ConfigurationTestResult {
        guard let credentials = try await credentialStore.credentials(for: revisionID) else {
            throw ConfigurationTestError.missingConfiguration
        }
        let fixtureAudioURL = try self.fixtureAudioURL()
        let noteID = NoteID()
        let attemptID = AttemptID()
        let note = Note(id: noteID, recordingSessionID: RecordingSessionID(), title: "Configuration test",
            titleSource: .timestamp, createdAt: clock.now, duration: 0, source: .iphone,
            captureOutcome: .completed, requiresReview: false, audioURL: fixtureAudioURL)
        let request = try requestBuilder.build(note: note, attemptID: attemptID, credentials: credentials,
            timestamp: Int64(clock.now.timeIntervalSince1970), event: "configuration.test",
            appVersion: appVersion, appBuild: appBuild)
        defer { request.removeBodyFile() }
        let response = try await transport.send(request)
        let passed = (200...299).contains(response.statusCode)
        guard passed else { return .init(passed: false, statusCode: response.statusCode, idempotencyConfirmed: false) }
        let expected = noteID.rawValue.uuidString.lowercased()
        let headerConfirmed = response.header("X-Whim-Note-ID")?.lowercased() == expected
        let jsonConfirmed: Bool
        if let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
           let responseID = object["note_id"] as? String {
            jsonConfirmed = responseID.lowercased() == expected
        } else {
            jsonConfirmed = false
        }
        return .init(passed: true, statusCode: response.statusCode,
            idempotencyConfirmed: headerConfirmed || jsonConfirmed)
    }
}
