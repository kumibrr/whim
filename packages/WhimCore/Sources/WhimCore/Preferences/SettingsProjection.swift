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
    public let availability: String
    public let lastSynchronizedAt: Date?
    public let resetState: String
    public static let unavailable = Self(availability: "unavailable", lastSynchronizedAt: nil, resetState: "unavailable")

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(availability, forKey: .availability)
        try values.encode(lastSynchronizedAt, forKey: .lastSynchronizedAt)
        try values.encode(resetState, forKey: .resetState)
    }
}

public struct SettingsProjection: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let preferences: PreferenceInput
    public let webhook: WebhookSettingsProjection?
    public let watch: WatchSettingsProjection
    public let onboardingCompleted: Bool
    public let permissions: PermissionProjection
    public init(preferences: PreferenceInput, webhook: WebhookSettingsProjection?, onboardingCompleted: Bool, permissions: PermissionProjection) {
        schemaVersion = WhimCoreVersion.schema; self.preferences = preferences; self.webhook = webhook
        watch = .unavailable
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
