import Foundation

public struct ConfigurationSaveCounts: Equatable, Sendable {
    public let unsent: Int
    public let failed: Int
    public let awaitingSetup: Int

    public init(unsent: Int, failed: Int, awaitingSetup: Int) {
        self.unsent = unsent
        self.failed = failed
        self.awaitingSetup = awaitingSetup
    }
}

public enum WebhookConfigurationSaveError: Error, CustomStringConvertible {
    case invalid([WebhookValidationError])

    public var description: String { "The webhook configuration is invalid." }
}

public struct WebhookConfigurationService: Sendable {
    private let store: any WhimStore
    private let credentialStore: any CredentialStore

    public init(store: any WhimStore, credentials: any CredentialStore) {
        self.store = store
        self.credentialStore = credentials
    }

    public func save(_ input: WebhookConfigurationInput, now: Date = Date()) async throws -> ConfigurationSaveCounts {
        let validation = WebhookValidator.validate(input, now: now)
        guard let validated = validation.value else { throw WebhookConfigurationSaveError.invalid(validation.errors) }
        let notes = try await store.listNotes(filter: .all)
        let unsent = notes.filter { $0.status != .sent }
        let result = ConfigurationSaveCounts(unsent: unsent.count,
            failed: unsent.count { $0.status == .failed },
            awaitingSetup: unsent.count { $0.status == .setupRequired })
        try await credentialStore.save(validated.credentials, for: validated.revision.id)
        do {
            try await store.saveConfigurationRevision(validated.revision)
        } catch {
            try? await credentialStore.remove(for: validated.revision.id)
            throw error
        }
        return result
    }
}
