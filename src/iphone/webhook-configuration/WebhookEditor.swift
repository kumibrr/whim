import Foundation
import Observation
import WhimCore

@MainActor @Observable public final class WebhookEditor {
    public var endpoint = "" { didSet { clearOutcome() } }
    public var bearer = SecretPatch(action: .preserve) { didSet { clearOutcome() } }
    public var hmac = SecretPatch(action: .preserve) { didSet { clearOutcome() } }
    public var headers: [HeaderPatch]? { didSet { clearOutcome() } }
    public var newName = "" { didSet { clearOutcome() } }
    public var newValue = "" { didSet { clearOutcome() } }
    public var newSecret = true
    public private(set) var isAddingHeader = false
    public private(set) var error: IPhoneError?
    public private(set) var message: String?
    public private(set) var offersRetry = false
    public private(set) var isPending = false
    private let client: any WhimClient
    private var draftBase: [HeaderPatch] = []
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    public var isDirty: Bool { !endpoint.isEmpty || bearer.action != .preserve || hmac.action != .preserve || headers != nil || !newName.isEmpty || !newValue.isEmpty }
    public init(client: any WhimClient) { self.client = client }
    public func existingHeaders(_ configuration: WebhookSettingsProjection?) -> [HeaderPatch] {
        headers ?? (configuration?.customHeaders.map { header in
            HeaderPatch(name: header.name, action: .preserve, value: nil, isSecret: header.isSecret)
        } ?? [])
    }
    /// Shows the new-header fields; a previously filled draft is kept as a pending header.
    public func addHeader(configuration: WebhookSettingsProjection?) {
        if isAddingHeader, !newName.isEmpty { headers = existingHeaders(configuration) + [draftHeader] }
        draftBase = existingHeaders(configuration)
        newName = ""; newValue = ""; newSecret = true; isAddingHeader = true
    }
    public func cancelHeader() { newName = ""; newValue = ""; newSecret = true; isAddingHeader = false }
    public func removeHeader(at index: Int, configuration: WebhookSettingsProjection?) {
        var values = existingHeaders(configuration)
        guard values.indices.contains(index) else { return }
        values.remove(at: index); headers = values
    }
    public func save() async {
        if let pendingSave { await pendingSave.value; return }
        guard !isPending else { return }
        let task = Task { @MainActor in
            await perform {
                let result = try await client.patchWebhook(.init(endpoint: endpoint.isEmpty ? nil : endpoint,
                    bearerToken: bearer, hmacSecret: hmac, customHeaders: pendingHeaders))
                endpoint = ""; bearer = .init(action: .preserve); hmac = .init(action: .preserve); headers = nil
                cancelHeader()
                message = "Webhook saved. Test it to check delivery."
                offersRetry = result.failedCount + result.setupRequiredCount > 0
            }
        }
        pendingSave = task
        await task.value
        pendingSave = nil
    }
    /// A blur and a button tap can request the same save; both await its completion.
    public func saveIfNeeded() async {
        if pendingSave != nil || isDirty { await save() }
    }
    public func test(saveChanges: Bool = false) async {
        if saveChanges && (isDirty || pendingSave != nil) {
            await saveIfNeeded()
            guard error == nil else { return }
        }
        guard !isDirty else { return }
        await perform {
            let result = try await client.testWebhook()
            offersRetry = result.passed
            message = result.passed
                ? (result.idempotencyConfirmed ? "Test passed. Idempotency confirmed." : "Test passed, but server-side idempotency could not be confirmed. Configure your server to deduplicate Note IDs.")
                : "Test failed\(result.statusCode.map { " · HTTP \($0)" } ?? ""). Check your configuration."
        }
    }
    public func retryUnsent() async {
        await perform {
            let count = try await client.retryAllFailed()
            message = "\(count) Notes offered for delivery."; offersRetry = false
        }
    }
    private var draftHeader: HeaderPatch { HeaderPatch(name: newName, action: .replace, value: newValue, isSecret: newSecret) }
    private var pendingHeaders: [HeaderPatch]? {
        isAddingHeader && !newName.isEmpty ? (headers ?? draftBase) + [draftHeader] : headers
    }
    private func perform(_ operation: () async throws -> Void) async {
        guard !isPending else { return }; isPending = true; clearOutcome()
        defer { isPending = false }
        do { try await operation() } catch is CancellationError {} catch { self.error = IPhoneError(error) }
    }
    private func clearOutcome() { error = nil; message = nil; offersRetry = false }
}
