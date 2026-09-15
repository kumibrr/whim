import Foundation

public struct SecretPatch: Codable, Sendable {
    public enum Action: String, Codable, Sendable { case preserve, replace, clear }
    public let action: Action
    public let value: String?
    public init(action: Action, value: String? = nil) { self.action = action; self.value = value }
    func applying(to existing: String?) throws -> String? {
        switch action {
        case .preserve: return existing
        case .clear: return nil
        case .replace:
            guard let value, !value.isEmpty else { throw WhimServiceError.invalidConfiguration(field: "secret") }
            return value
        }
    }
}

public struct HeaderPatch: Codable, Sendable {
    public let name: String
    public let action: SecretPatch.Action
    public let value: String?
    public let isSecret: Bool
}

public struct WebhookPatch: Codable, Sendable {
    public let endpoint: String?
    public let bearerToken: SecretPatch?
    public let hmacSecret: SecretPatch?
    public let customHeaders: [HeaderPatch]?
    public init(endpoint: String? = nil, bearerToken: SecretPatch? = nil,
                hmacSecret: SecretPatch? = nil, customHeaders: [HeaderPatch]? = nil) {
        self.endpoint = endpoint; self.bearerToken = bearerToken
        self.hmacSecret = hmacSecret; self.customHeaders = customHeaders
    }

    public func applying(to existing: StoredWebhookCredentials?) throws -> WebhookConfigurationInput {
        guard let endpoint = endpoint ?? existing?.endpoint.absoluteString else {
            throw WhimServiceError.invalidConfiguration(field: "endpoint")
        }
        let headers = try customHeaders.map { patches in
            try patches.compactMap { patch -> CustomHeaderInput? in
                let previous = existing?.customHeaders.first { $0.name.caseInsensitiveCompare(patch.name) == .orderedSame }
                switch patch.action {
                case .clear: return nil
                case .preserve:
                    guard let previous else { throw WhimServiceError.invalidConfiguration(field: "customHeaders") }
                    return previous
                case .replace:
                    guard let value = patch.value else { throw WhimServiceError.invalidConfiguration(field: "customHeaders") }
                    return .init(name: patch.name, value: value, isSecret: patch.isSecret)
                }
            }
        } ?? existing?.customHeaders ?? []
        return try .init(endpoint: endpoint,
            bearerToken: bearerToken?.applying(to: existing?.bearerToken) ?? (bearerToken == nil ? existing?.bearerToken : nil),
            hmacSecret: hmacSecret?.applying(to: existing?.hmacSecret) ?? (hmacSecret == nil ? existing?.hmacSecret : nil),
            customHeaders: headers)
    }
}
