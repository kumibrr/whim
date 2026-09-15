import XCTest

@MainActor
final class WatchRecordingUITests: XCTestCase {
    func testLaunchCapturesAndStopSavesLocallyWithoutConfiguration() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments
        app.launch()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["watch-recorder"].exists)
        app.buttons["watch-stop"].tap()
        XCTAssertTrue(app.buttons["watch-recent-notes"].waitForExistence(timeout: 10))
        app.buttons["watch-recent-notes"].tap()
        XCTAssertTrue(app.staticTexts["Setup required"].waitForExistence(timeout: 10))
    }
}

extension WatchRecordingUITests {
    func testDeniedMicrophoneShowsExplanationWithoutStartingCapture() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments + ["-WhimWatchMicrophoneDenied"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Microphone access is required to capture a Note."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["watch-stop"].exists)
    }

    func testDiscardRequiresConfirmationAndLeavesNoNote() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments
        app.launch()
        XCTAssertTrue(app.buttons["watch-discard"].waitForExistence(timeout: 10))
        app.buttons["watch-discard"].tap()
        XCTAssertTrue(app.buttons["AX_ActionContentControllerCancelButton"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["AX_ActionContentControllerCancelButton"].firstMatch.tap()
        XCTAssertTrue(app.buttons["watch-stop"].exists)
        app.buttons["watch-discard"].tap()
        app.buttons["Discard Recording"].tap()
        app.buttons["watch-recent-notes"].tap()
        XCTAssertTrue(app.staticTexts["No Notes yet"].waitForExistence(timeout: 5))
    }

    func testForegroundRestoresCaptureAndDoesNotRestartAfterStop() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments
        app.launch()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 10))
        app.buttons["watch-recent-notes"].tap()
        XCTAssertTrue(app.staticTexts["No Notes yet"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 5))
        app.buttons["watch-stop"].tap()
        XCTAssertTrue(app.buttons["watch-record"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["watch-record"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["watch-stop"].exists)
    }
}
