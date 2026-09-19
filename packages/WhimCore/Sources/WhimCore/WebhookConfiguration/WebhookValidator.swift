import Foundation

public struct CustomHeaderInput: Codable, Equatable, Sendable {
    public let name: String
    public let value: String
    public let isSecret: Bool

    public init(name: String, value: String, isSecret: Bool = false) {
        self.name = name
        self.value = value
        self.isSecret = isSecret
    }
}

public struct WebhookConfigurationInput: Sendable, CustomStringConvertible {
    public let endpoint: String
    public let bearerToken: String?
    public let hmacSecret: String?
    public let customHeaders: [CustomHeaderInput]

    public init(endpoint: String, bearerToken: String? = nil, hmacSecret: String? = nil,
                customHeaders: [CustomHeaderInput] = []) {
        self.endpoint = endpoint
        self.bearerToken = bearerToken
        self.hmacSecret = hmacSecret
        self.customHeaders = customHeaders
    }

    public var description: String { "WebhookConfigurationInput(<redacted>)" }
}

public struct StoredWebhookCredentials: Codable, Equatable, Sendable, CustomStringConvertible {
    public let endpoint: URL
    public let bearerToken: String?
    public let hmacSecret: String?
    public let customHeaders: [CustomHeaderInput]

    public init(endpoint: URL, bearerToken: String?, hmacSecret: String?, customHeaders: [CustomHeaderInput]) {
        self.endpoint = endpoint
        self.bearerToken = bearerToken
        self.hmacSecret = hmacSecret
        self.customHeaders = customHeaders
    }

    public var description: String { "StoredWebhookCredentials(<redacted>)" }
}

public enum WebhookValidationField: Equatable, Sendable {
    case endpoint
    case customHeaders
    case customHeader(Int)
}

public struct WebhookValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    public let field: WebhookValidationField
    private let message: String

    init(field: WebhookValidationField, message: String) {
        self.field = field
        self.message = message
    }

    public var description: String { message }
}

public struct ValidatedWebhookConfiguration: Sendable {
    public let revision: ConfigurationRevision
    public let credentials: StoredWebhookCredentials
}

public struct WebhookValidationResult: Sendable {
    public let value: ValidatedWebhookConfiguration?
    public let errors: [WebhookValidationError]
}

public enum WebhookValidator {
    private static let reservedNames: Set<String> = [
        "authorization", "content-type", "content-length", "host", "transfer-encoding",
        "x-whim-note-id", "x-whim-attempt-id", "x-whim-timestamp",
        "x-whim-metadata-sha256", "x-whim-audio-sha256", "x-whim-signature",
    ]
    private static let tokenCharacters = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    public static func validate(_ input: WebhookConfigurationInput, now: Date = Date(),
                                revisionID: ConfigurationRevisionID = ConfigurationRevisionID()) -> WebhookValidationResult {
        var errors: [WebhookValidationError] = []
        let components = URLComponents(string: input.endpoint)
        let url = components?.url
        let usesHTTPS = components?.scheme?.lowercased() == "https"
        let usesPrivateNetworkHTTP = components?.scheme?.lowercased() == "http" &&
            isPrivateNetworkIPv4Address(components?.host)
        if (!usesHTTPS && !usesPrivateNetworkHTTP) || components?.host?.isEmpty != false ||
            components?.user != nil || components?.password != nil || url == nil {
            errors.append(.init(field: .endpoint, message: "Enter an HTTPS webhook URL, or an HTTP URL on a private network, without embedded credentials."))
        }
        if input.customHeaders.count > 10 {
            errors.append(.init(field: .customHeaders, message: "Use no more than ten custom headers."))
        }
        var names: Set<String> = []
        for (index, header) in input.customHeaders.enumerated() {
            let lowered = header.name.lowercased()
            let scalars = header.name.unicodeScalars
            if header.name.isEmpty || scalars.contains(where: { !tokenCharacters.contains($0) }) ||
                reservedNames.contains(lowered) || !names.insert(lowered).inserted ||
                header.value.contains("\r") || header.value.contains("\n") {
                errors.append(.init(field: .customHeader(index), message: "This custom header name or value is not allowed."))
            }
        }
        guard errors.isEmpty, let url, let endpoint = SanitizedEndpoint(url: url) else {
            return WebhookValidationResult(value: nil, errors: errors)
        }
        let revision = ConfigurationRevision(id: revisionID, changedAt: now, endpoint: endpoint)
        let credentials = StoredWebhookCredentials(endpoint: url,
            bearerToken: normalized(input.bearerToken), hmacSecret: normalized(input.hmacSecret),
            customHeaders: input.customHeaders)
        return WebhookValidationResult(value: .init(revision: revision, credentials: credentials), errors: [])
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func isPrivateNetworkIPv4Address(_ host: String?) -> Bool {
        guard let host else { return false }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, let first = UInt8(octets[0]), let second = UInt8(octets[1]) else { return false }
        return first == 10 || first == 127 ||
            (first == 172 && (16...31).contains(second)) ||
            (first == 192 && second == 168)
    }
}
