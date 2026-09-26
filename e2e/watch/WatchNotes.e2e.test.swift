import XCTest

@MainActor
final class WatchNotesUITests: XCTestCase {
    func testLocalPlaybackAndConfirmedDeletion() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments
        app.launch()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 10))
        app.buttons["watch-stop"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Setup required"].waitForExistence(timeout: 5))
        app.staticTexts["Setup required"].tap()
        XCTAssertTrue(app.buttons["watch-play"].waitForExistence(timeout: 5))
        app.buttons["watch-play"].tap()
        XCTAssertTrue(app.buttons["watch-stop-playback"].waitForExistence(timeout: 5))
        app.buttons["watch-stop-playback"].tap()
        app.swipeUp()
        app.buttons["watch-delete"].tap()
        XCTAssertTrue(app.buttons["Delete Note"].waitForExistence(timeout: 5))
        app.buttons["Delete Note"].tap()
        XCTAssertTrue(app.staticTexts["No Notes yet"].waitForExistence(timeout: 5))
    }

    func testConfiguredOfflineCaptureRemainsQueued() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments + ["-WhimWatchConfigured", "-WhimFixtureOffline"]
        app.launch()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 10))
        app.buttons["watch-stop"].tap()
        XCTAssertTrue(app.staticTexts["Webhook available"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Queued"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["watch-sync-now"].waitForExistence(timeout: 5))
        app.buttons["watch-sync-now"].tap()
        XCTAssertTrue(app.staticTexts["No connection. Notes stay queued."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Queued"].exists)
    }

    func testDirectDeliveryFailureCanBeRetriedSuccessfully() async throws {
        let base = try XCTUnwrap(ProcessInfo.processInfo.environment["WHIM_WATCH_WEBHOOK_URL"])
        try await control(base, path: "/reset")
        try await control(base, path: "/response", body: "{\"status\":400}")
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments + ["-WhimWatchConfigured",
            "-WhimFixtureWebhookURL", base + "/receive"]
        app.launch()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 10))
        app.buttons["watch-stop"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Failed"].waitForExistence(timeout: 10))
        app.staticTexts["Failed"].tap()
        try await control(base, path: "/response", body: "{\"status\":200}")
        app.swipeUp()
        app.buttons["watch-retry"].tap()
        XCTAssertTrue(app.staticTexts["Sent"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["watch-retry"].exists)
        let (data, _) = try await URLSession.shared.data(from: URL(string: base + "/state")!)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let received = try XCTUnwrap(object["received"] as? [[String: Any]])
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0]["noteID"] as? String, received[1]["noteID"] as? String)
        let metadata = try XCTUnwrap(received[0]["json"] as? [String: Any])
        XCTAssertEqual(metadata["source"] as? String, "apple_watch")
        XCTAssertEqual(metadata["title_source"] as? String, "timestamp")
    }

    func testSlowRetryLeavesStopAndConfirmedDeleteUsable() async throws {
        let base = try XCTUnwrap(ProcessInfo.processInfo.environment["WHIM_WATCH_WEBHOOK_URL"])
        try await control(base, path: "/reset")
        try await control(base, path: "/response", body: "{\"status\":400}")
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments + ["-WhimWatchConfigured",
            "-WhimFixtureWebhookURL", base + "/receive"]
        app.launch()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 10))
        app.buttons["watch-stop"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Failed"].waitForExistence(timeout: 10))
        let oldRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "watch-note-")).firstMatch
        let oldID = oldRow.identifier
        app.swipeDown()
        app.buttons["watch-record"].tap()
        app.swipeUp()
        app.buttons[oldID].tap()
        try await control(base, path: "/response", body: "{\"status\":200,\"delay_ms\":30000}")
        app.swipeUp()
        app.buttons["watch-retry"].tap()
        XCTAssertTrue(app.staticTexts["Sending"].waitForExistence(timeout: 5))
        app.buttons["BackButton"].tap()
        app.swipeDown()
        XCTAssertTrue(app.buttons["watch-stop"].isEnabled)
        app.buttons["watch-stop"].tap()
        XCTAssertTrue(app.buttons["watch-record"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons[oldID].tap()
        XCTAssertTrue(app.staticTexts["Sending"].exists)
        app.swipeUp()
        app.buttons["watch-delete"].tap()
        app.buttons["Delete Note"].tap()
        XCTAssertTrue(app.buttons[oldID].waitForNonExistence(timeout: 5))
    }

    private func control(_ base: String, path: String, body: String? = nil) async throws {
        var request = URLRequest(url: URL(string: base + path)!)
        request.httpMethod = "POST"
        request.httpBody = body?.data(using: .utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 204)
    }
}
