import XCTest
import WhimCore
@testable import WhimIPhone

@MainActor final class WebhookErrorLogIntegrationTests: XCTestCase {
    func testLogShowsReceivedMessagesAndDescribesMissingOnes() async throws {
        let harness = try WhimFacadeHarness(responses: [
            HTTPResponse(statusCode: 400, body: Data("  Missing field: event\n".utf8)),
            HTTPResponse(statusCode: 500),
        ])
        defer { harness.remove() }
        _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"))
        let client = harness.makeService()
        let log = WebhookErrorLog(client: client)
        await log.refresh()
        XCTAssertEqual(log.entries, [])

        _ = try await client.startRecording(source: .iphone)
        let stopped = try await client.stopRecording()
        let note = try XCTUnwrap(stopped)
        for _ in 0..<100 where try await client.listNotes(filter: .failed).isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        harness.clock.advance(by: 60)
        try await client.retry(noteID: note.id)
        await log.refresh()

        XCTAssertNil(log.error)
        XCTAssertEqual(log.entries.map(\.status), ["HTTP 500", "HTTP 400"])
        XCTAssertEqual(log.entries.map(\.message), ["The destination returned no message.", "Missing field: event"])
        XCTAssertEqual(log.entries.first?.noteID, note.id)
    }
}
