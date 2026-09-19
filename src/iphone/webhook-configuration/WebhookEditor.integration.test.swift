import XCTest
import WhimCore
@testable import WhimIPhone

@MainActor final class WebhookEditorIntegrationTests: XCTestCase {
    func testEditingPreservesSavedSecretsAndQueryAndClearsExplicitSecret() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService()
        _ = try await client.updateWebhook(.init(endpoint: "https://example.com/receive?token=private", bearerToken: "bearer", hmacSecret: "hmac", customHeaders: [.init(name: "X-Custom", value: "private", isSecret: true)]))
        let editor = WebhookEditor(client: client)
        editor.bearer = .init(action: .clear)
        XCTAssertTrue(editor.isDirty)
        await editor.save()
        XCTAssertNil(editor.error)
        XCTAssertFalse(editor.isDirty)
        let settings = try await client.settings()
        XCTAssertEqual(settings.webhook?.hasBearerToken, false)
        XCTAssertEqual(settings.webhook?.hasHMACSecret, true)
        XCTAssertEqual(settings.webhook?.customHeaders.count, 1)
        let revision = try await harness.store.latestConfigurationRevision()
        let stored = await harness.credentials.credentials(for: try XCTUnwrap(revision).id)
        XCTAssertEqual(stored?.endpoint.absoluteString, "https://example.com/receive?token=private")
    }
    func testInvalidConfigurationIsVisibleAndDoesNotDiscardEdits() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let editor = WebhookEditor(client: harness.makeService())
        editor.endpoint = "http://example.com"
        await editor.save()
        XCTAssertNotNil(editor.error)
        XCTAssertEqual(editor.endpoint, "http://example.com")
        XCTAssertTrue(editor.isDirty)
    }
}
