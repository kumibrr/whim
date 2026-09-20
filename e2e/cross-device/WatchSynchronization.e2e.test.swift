import XCTest

/// Peer envelopes are injected at the DEBUG system boundary. Real transferFile
/// and two physical devices racing remain paired-device acceptance cases.
@MainActor
final class WatchSynchronizationUITests: XCTestCase {
    func testFileAndStateArriveInEitherOrderWithDuplicates() {
        for order in ["file-first", "state-first"] {
            let app = XCUIApplication()
            app.launchArguments = WatchUITestConfiguration.arguments + ["-WhimPeerScenario", order]
            app.launch()
            XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 15))
            app.swipeUp()
            XCTAssertTrue(app.staticTexts["From paired Watch"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Sent"].exists)
            app.staticTexts["From paired Watch"].tap()
            XCTAssertTrue(app.buttons["watch-play"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testDirectWatchHTTPFailureCannotRegressPeerReceiptInEitherOrder() async throws {
        let base = try XCTUnwrap(ProcessInfo.processInfo.environment["WHIM_WATCH_WEBHOOK_URL"])
        for order in ["receipt-first", "failure-first"] {
            var request = URLRequest(url: URL(string: base + "/reset")!)
            request.httpMethod = "POST"
            _ = try await URLSession.shared.data(for: request)
            request.url = URL(string: base + "/response")!
            request.httpBody = Data("{\"status\":400,\"delay_ms\":250}".utf8)
            _ = try await URLSession.shared.data(for: request)
            let app = XCUIApplication()
            app.launchArguments = WatchUITestConfiguration.arguments + ["-WhimWatchConfigured",
                "-WhimFixtureWebhookURL", base + "/receive", "-WhimPeerScenario", order]
            app.launch()
            XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 15))
            app.buttons["watch-stop"].tap()
            app.swipeUp()
            XCTAssertTrue(app.staticTexts["Peer confirmed title"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Sent"].exists)
            let (data, _) = try await URLSession.shared.data(from: URL(string: base + "/state")!)
            let state = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let received = try XCTUnwrap(state["received"] as? [[String: Any]])
            XCTAssertEqual(received.count, 1, "Only the actual Watch request reaches this receiver; peer Receipt is injected")
            app.terminate()
        }
    }
}
