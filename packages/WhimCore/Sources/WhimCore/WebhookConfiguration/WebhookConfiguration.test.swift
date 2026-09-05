import Foundation
import XCTest
@testable import WhimCore

final class WebhookConfigurationTests: XCTestCase {
    func testRejectsCredentialBearingEndpoint() {
        let endpoint = URL(string: "https://user:password@example.com/whim")!

        XCTAssertNil(WebhookConfiguration(endpoint: endpoint))
    }

    func testDecodingRejectsCredentialBearingEndpoint() throws {
        let revisionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let payload = """
        {
          "revisionID": { "rawValue": "\(revisionID.uuidString)" },
          "endpoint": "https://user:password@example.com/whim",
          "customHeaderNames": []
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(WebhookConfiguration.self, from: payload))
    }
}
