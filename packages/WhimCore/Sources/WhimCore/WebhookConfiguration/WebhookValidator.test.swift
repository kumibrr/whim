import Foundation
import XCTest
@testable import WhimCore

final class WebhookValidatorTests: XCTestCase {
    // Break: a cleartext, credential-bearing, or hostless destination becomes usable.
    func testEndpointValidationIsFieldSpecificAndNeverEchoesInput() {
        let secret = "DO-NOT-ECHO"
        for endpoint in ["http://example.com/hook", "https://user:\(secret)@example.com/hook", "https:///hook"] {
            let errors = WebhookValidator.validate(WebhookConfigurationInput(endpoint: endpoint)).errors
            XCTAssertEqual(errors.first?.field, .endpoint)
            XCTAssertFalse(errors.map(\.description).joined().contains(secret))
        }
    }

    // Break: an eleventh header or mixed-case contract header overrides Whim's request.
    func testRejectsTooManyAndCaseInsensitiveReservedHeaders() {
        let many = (0...10).map { CustomHeaderInput(name: "X-Custom-\($0)", value: "value") }
        XCTAssertTrue(WebhookValidator.validate(WebhookConfigurationInput(endpoint: "https://example.com", customHeaders: many)).errors.contains { $0.field == .customHeaders })
        for name in ["authorization", "CONTENT-type", "x-WHIM-note-ID", "Host", "Content-Length"] {
            let result = WebhookValidator.validate(WebhookConfigurationInput(endpoint: "https://example.com", customHeaders: [.init(name: name, value: "private")]))
            XCTAssertEqual(result.errors.first?.field, .customHeader(0))
            XCTAssertFalse(result.errors.first!.description.contains("private"))
        }
    }

    // Break: query values or marked-secret custom values enter the non-secret revision projection.
    func testValidInputSeparatesAllSecretsFromRevision() throws {
        let input = WebhookConfigurationInput(
            endpoint: "https://Example.COM:8443/hook?api_key=QUERY-SECRET",
            bearerToken: "BEARER-SECRET",
            hmacSecret: "HMAC-SECRET",
            customHeaders: [
                .init(name: "X-Public", value: "visible"),
                .init(name: "X-Private", value: "HEADER-SECRET", isSecret: true),
            ]
        )
        let validated = try XCTUnwrap(WebhookValidator.validate(input).value)
        XCTAssertEqual(validated.revision.endpoint, SanitizedEndpoint(scheme: "https", host: "example.com", port: 8443, path: "/hook"))
        let encodedRevision = String(decoding: try JSONEncoder().encode(validated.revision), as: UTF8.self)
        for secret in ["QUERY-SECRET", "BEARER-SECRET", "HMAC-SECRET", "HEADER-SECRET", "visible"] {
            XCTAssertFalse(encodedRevision.contains(secret))
        }
        XCTAssertEqual(validated.credentials.endpoint.absoluteString, input.endpoint)
        XCTAssertEqual(validated.credentials.customHeaders.map(\.name), ["X-Public", "X-Private"])
    }
}
