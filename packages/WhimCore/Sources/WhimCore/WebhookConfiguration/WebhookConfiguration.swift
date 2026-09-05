import Foundation

public struct ConfigurationRevisionID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: UUID())
    }
}

public struct WebhookConfiguration: Codable, Equatable, Sendable {
    public let revisionID: ConfigurationRevisionID
    public let endpoint: URL
    public let customHeaderNames: [String]

    public init?(
        revisionID: ConfigurationRevisionID = ConfigurationRevisionID(),
        endpoint: URL,
        customHeaderNames: [String] = []
    ) {
        guard endpoint.user == nil, endpoint.password == nil else { return nil }
        self.revisionID = revisionID
        self.endpoint = endpoint
        self.customHeaderNames = customHeaderNames
    }

    public var isUsable: Bool {
        endpoint.scheme?.lowercased() == "https" &&
            endpoint.host?.isEmpty == false &&
            endpoint.user == nil &&
            endpoint.password == nil
    }

    private enum CodingKeys: String, CodingKey {
        case revisionID
        case endpoint
        case customHeaderNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let revisionID = try container.decode(ConfigurationRevisionID.self, forKey: .revisionID)
        let endpoint = try container.decode(URL.self, forKey: .endpoint)
        let customHeaderNames = try container.decode([String].self, forKey: .customHeaderNames)
        guard let configuration = WebhookConfiguration(
            revisionID: revisionID,
            endpoint: endpoint,
            customHeaderNames: customHeaderNames
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .endpoint,
                in: container,
                debugDescription: "Webhook endpoint URLs must not contain user-info credentials."
            )
        }
        self = configuration
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(revisionID, forKey: .revisionID)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(customHeaderNames, forKey: .customHeaderNames)
    }
}
