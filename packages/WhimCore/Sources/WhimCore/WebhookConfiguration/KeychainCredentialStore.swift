import Foundation
import Security

public actor KeychainCredentialStore: CredentialStore {
    private let service: String

    public init(service: String = "app.whim.webhook") {
        self.service = service
    }

    public func save(_ credentials: StoredWebhookCredentials, for revisionID: ConfigurationRevisionID) throws {
        let data = try JSONEncoder().encode(credentials)
        let account = revisionID.rawValue.uuidString.lowercased()
        let base = query(account: account)
        let updateStatus = SecItemUpdate(base as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw CredentialStoreError.unavailable }
        var insertion = base
        insertion[kSecValueData] = data
        insertion[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
            throw CredentialStoreError.unavailable
        }
    }

    public func credentials(for revisionID: ConfigurationRevisionID) throws -> StoredWebhookCredentials? {
        var lookup = query(account: revisionID.rawValue.uuidString.lowercased())
        lookup[kSecReturnData] = true
        lookup[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CredentialStoreError.unavailable }
        do { return try JSONDecoder().decode(StoredWebhookCredentials.self, from: data) }
        catch { throw CredentialStoreError.malformed }
    }

    public func remove(for revisionID: ConfigurationRevisionID) throws {
        let status = SecItemDelete(query(account: revisionID.rawValue.uuidString.lowercased()) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialStoreError.unavailable }
    }

    public func removeAll() throws {
        let status = SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialStoreError.unavailable }
    }

    private func query(account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }
}
