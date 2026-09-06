import Foundation

public protocol CredentialStore: Sendable {
    func save(_ credentials: StoredWebhookCredentials, for revisionID: ConfigurationRevisionID) async throws
    func credentials(for revisionID: ConfigurationRevisionID) async throws -> StoredWebhookCredentials?
    func remove(for revisionID: ConfigurationRevisionID) async throws
    func removeAll() async throws
}

public enum CredentialStoreError: Error, CustomStringConvertible {
    case unavailable
    case malformed

    public var description: String {
        switch self {
        case .unavailable: "Credentials are unavailable."
        case .malformed: "Stored credentials could not be read."
        }
    }
}
