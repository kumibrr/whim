import Foundation

public struct WebhookSettingsProjection: Codable, Equatable, Sendable {
    public struct Header: Codable, Equatable, Sendable { public let name: String; public let isSecret: Bool }
    public let revisionID: String
    public let destination: SanitizedEndpointProjection
    public let hasBearerToken: Bool
    public let hasHMACSecret: Bool
    public let customHeaders: [Header]
    public init(revision: ConfigurationRevision, credentials: StoredWebhookCredentials) {
        revisionID = revision.id.rawValue.uuidString.lowercased()
        destination = .init(revision.endpoint)
        hasBearerToken = credentials.bearerToken != nil
        hasHMACSecret = credentials.hmacSecret != nil
        customHeaders = credentials.customHeaders.map { .init(name: $0.name, isSecret: $0.isSecret) }
    }
}

public struct WatchSettingsProjection: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case availability, availabilityReason, lastSynchronizedAt, resetState, recordingPreferencesState, connectionDetails
    }
    public let availability: String
    /// `PeerUnavailabilityReason` raw value while unavailable and the system knows why.
    public let availabilityReason: String?
    public let connectionDetails: PeerConnectionDetails?
    public let lastSynchronizedAt: Date?
    public let resetState: String
    public let recordingPreferencesState: String
    public init(availability: String, lastSynchronizedAt: Date?, resetState: String,
                recordingPreferencesState: String = "unavailable", availabilityReason: String? = nil,
                connectionDetails: PeerConnectionDetails? = nil) {
        self.availability = availability; self.lastSynchronizedAt = lastSynchronizedAt
        self.availabilityReason = availabilityReason
        self.connectionDetails = connectionDetails
        self.resetState = resetState; self.recordingPreferencesState = recordingPreferencesState
    }
    public static let unavailable = Self(availability: "unavailable", lastSynchronizedAt: nil, resetState: "unavailable")

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(availability: try values.decode(String.self, forKey: .availability),
            lastSynchronizedAt: try values.decodeIfPresent(Date.self, forKey: .lastSynchronizedAt),
            resetState: try values.decode(String.self, forKey: .resetState),
            recordingPreferencesState: try values.decodeIfPresent(String.self, forKey: .recordingPreferencesState) ?? "unavailable",
            availabilityReason: try values.decodeIfPresent(String.self, forKey: .availabilityReason),
            connectionDetails: try values.decodeIfPresent(PeerConnectionDetails.self, forKey: .connectionDetails))
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(availability, forKey: .availability)
        try values.encodeIfPresent(availabilityReason, forKey: .availabilityReason)
        try values.encodeIfPresent(connectionDetails, forKey: .connectionDetails)
        try values.encode(lastSynchronizedAt, forKey: .lastSynchronizedAt)
        try values.encode(resetState, forKey: .resetState)
        try values.encode(recordingPreferencesState, forKey: .recordingPreferencesState)
    }
}

public struct SettingsProjection: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let preferences: PreferenceInput
    public let webhook: WebhookSettingsProjection?
    public let watch: WatchSettingsProjection
    public let onboardingCompleted: Bool
    public let permissions: PermissionProjection
    public init(preferences: PreferenceInput, webhook: WebhookSettingsProjection?, onboardingCompleted: Bool, permissions: PermissionProjection, watch: WatchSettingsProjection = .unavailable) {
        schemaVersion = WhimCoreVersion.schema; self.preferences = preferences; self.webhook = webhook
        self.watch = watch
        self.onboardingCompleted = onboardingCompleted
        self.permissions = permissions
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(preferences, forKey: .preferences)
        try values.encode(webhook, forKey: .webhook)
        try values.encode(watch, forKey: .watch)
        try values.encode(onboardingCompleted, forKey: .onboardingCompleted)
        try values.encode(permissions, forKey: .permissions)
    }
}
