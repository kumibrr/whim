import Foundation
import XCTest
@testable import WhimCore

final class DebugFixtureTransportIntegrationTests: XCTestCase {
    func testDebugLoopbackMappingPreservesContractAndRejectsRemoteOverride() async throws {
        let boundary = InspectFixtureTransport()
        let adapter = try XCTUnwrap(DebugFixtureTransport.from(arguments: ["app", "-WhimFixtureWebhookURL", "http://127.0.0.1:9876/receive"], base: boundary))
        let request = WebhookRequest(url: URL(string: "https://whim-fixture.invalid/receive")!, method: "POST", headers: ["X-Whim-Signature": "v1=digest"], bodyFileURL: URL(fileURLWithPath: "/tmp/body"), contentLength: 42)
        _ = try await adapter.send(request)
        let received = await boundary.request
        XCTAssertEqual(received?.url.absoluteString, "http://127.0.0.1:9876/receive")
        XCTAssertEqual(received?.headers["X-Whim-Signature"], "v1=digest")
        XCTAssertEqual(received?.bodyFileURL.path, "/tmp/body")
        XCTAssertThrowsError(try DebugFixtureTransport.from(arguments: ["app", "-WhimFixtureWebhookURL", "http://evil.example:9876/receive"], base: boundary))
    }
}
private actor InspectFixtureTransport: HTTPTransport {
    private(set) var request: WebhookRequest?
    func send(_ request: WebhookRequest) -> HTTPResponse { self.request = request; return .init(statusCode: 204) }
}
