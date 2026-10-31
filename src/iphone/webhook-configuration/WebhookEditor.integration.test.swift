import XCTest
import WhimCore
@testable import WhimIPhone

@MainActor final class WebhookEditorIntegrationTests: XCTestCase {
    func testEmptyBearerBlurPreservesButSubmitClearsAndNonemptySubmitReplaces() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService()
        _ = try await client.updateWebhook(.init(endpoint: "https://example.com/receive", bearerToken: "original", hmacSecret: "keep-hmac"))
        let editor = WebhookEditor(client: client)
        await editor.saveIfNeeded()
        let afterBlur = try await client.settings()
        XCTAssertEqual(afterBlur.webhook?.hasBearerToken, true)
        await editor.submitBearerToken()
        let afterEmptySubmit = try await client.settings()
        XCTAssertEqual(afterEmptySubmit.webhook?.hasBearerToken, false)
        XCTAssertEqual(afterEmptySubmit.webhook?.hasHMACSecret, true)
        editor.bearer = .init(action: .replace, value: "replacement")
        await editor.submitBearerToken()
        let latest = try await harness.store.latestConfigurationRevision()
        let revision = try XCTUnwrap(latest)
        let stored = await harness.credentials.credentials(for: revision.id)
        XCTAssertEqual(stored?.bearerToken, "replacement")
        XCTAssertFalse(editor.isDirty)
    }

    func testTestingStateEndsAfterSuccessFailureAndCancellation() async throws {
        for outcome in [200, 500, 0] {
            let harness = try WhimFacadeHarness(responses: [HTTPResponse(statusCode: outcome)])
            defer { harness.remove() }
            try Data("fixture".utf8).write(to: harness.root.appendingPathComponent("test.m4a"))
            let editor = WebhookEditor(client: harness.makeService())
            editor.endpoint = "https://example.com/receive"
            await editor.save()
            XCTAssertFalse(editor.isTesting)
            await harness.transport.suspendResponses()
            let pending = Task { await editor.test() }
            await harness.transport.waitForRequestCount(1)
            XCTAssertTrue(editor.isTesting)
            if outcome == 0 { pending.cancel() }
            await harness.transport.resumeResponses()
            await pending.value
            XCTAssertFalse(editor.isTesting)
            XCTAssertFalse(editor.isPending)
        }
    }

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
