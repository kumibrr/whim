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
    public private(set) var error: IPhoneError?
    public private(set) var message: String?
    public private(set) var offersRetry = false
    public private(set) var isPending = false
    private let client: any WhimClient
    public var isDirty: Bool { !endpoint.isEmpty || bearer.action != .preserve || hmac.action != .preserve || headers != nil || !newName.isEmpty || !newValue.isEmpty }
    public init(client: any WhimClient) { self.client = client }
    public func existingHeaders(_ configuration: WebhookSettingsProjection?) -> [HeaderPatch] {
        headers ?? (configuration?.customHeaders.map { header in
            HeaderPatch(name: header.name, action: .preserve, value: nil, isSecret: header.isSecret)
        } ?? [])
    }
    public func addHeader(configuration: WebhookSettingsProjection?) {
        headers = existingHeaders(configuration) + [HeaderPatch(name: newName, action: .replace, value: newValue, isSecret: newSecret)]
        newName = ""; newValue = ""
    }
    public func removeHeader(at index: Int, configuration: WebhookSettingsProjection?) {
        var values = existingHeaders(configuration)
        guard values.indices.contains(index) else { return }
        values.remove(at: index); headers = values
    }
    public func save() async {
        await perform {
            let result = try await client.patchWebhook(.init(endpoint: endpoint.isEmpty ? nil : endpoint,
                bearerToken: bearer, hmacSecret: hmac, customHeaders: headers))
            endpoint = ""; bearer = .init(action: .preserve); hmac = .init(action: .preserve); headers = nil
            message = "Webhook saved. Test it to check delivery."
            offersRetry = result.failedCount + result.setupRequiredCount > 0
        }
    }
    public func test() async {
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
    private func perform(_ operation: () async throws -> Void) async {
        guard !isPending else { return }; isPending = true; clearOutcome()
        defer { isPending = false }
        do { try await operation() } catch is CancellationError {} catch { self.error = IPhoneError(error) }
    }
    private func clearOutcome() { error = nil; message = nil; offersRetry = false }
}
