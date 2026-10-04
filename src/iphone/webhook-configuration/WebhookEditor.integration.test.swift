import XCTest
import WhimCore
@testable import WhimIPhone

@MainActor final class WebhookEditorIntegrationTests: XCTestCase {
    func testSavingKeepsEndpointEditableWithoutPendingChanges() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService()
        let editor = WebhookEditor(client: client)
        editor.endpoint = "https://example.com/receive?token=private"

        await editor.saveIfNeeded()

        XCTAssertNil(editor.error)
        XCTAssertEqual(editor.endpoint, "https://example.com/receive?token=private")
        XCTAssertFalse(editor.isDirty)
        let saved = try await client.settings()
        let revisionID = try XCTUnwrap(saved.webhook).revisionID
        await editor.saveIfNeeded()
        let unchanged = try await client.settings()
        XCTAssertEqual(unchanged.webhook?.revisionID, revisionID)

        editor.endpoint = "https://example.com/updated"
        XCTAssertTrue(editor.isDirty)
        await editor.saveIfNeeded()
        XCTAssertEqual(editor.endpoint, "https://example.com/updated")
        XCTAssertFalse(editor.isDirty)
        let updated = try await client.settings()
        XCTAssertEqual(updated.webhook?.destination.path, "/updated")
    }

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
