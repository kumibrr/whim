import XCTest

@MainActor
final class WatchRecordingUITests: XCTestCase {
    func testLaunchCapturesAndStopSavesLocallyWithoutConfiguration() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments
        app.launch()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["watch-waveform"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["watch-recorder"].exists)
        let historyHeading = app.staticTexts["watch-previous-notes"]
        XCTAssertTrue(!historyHeading.exists
            || historyHeading.frame.minY >= app.windows.firstMatch.frame.maxY - 2)
        app.buttons["watch-stop"].tap()
        XCTAssertTrue(app.buttons["watch-record"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["watch-recent-notes"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Setup required"].waitForExistence(timeout: 10))
    }
}

extension WatchRecordingUITests {
    func testPreviousNotesTitleUsesNavigationToolbar() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments
        app.launch()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Previous Notes"].exists)
        app.buttons["watch-stop"].tap()

        app.swipeUp()
        let notesToolbar = app.navigationBars["Previous Notes"]
        XCTAssertTrue(notesToolbar.waitForExistence(timeout: 5))
        let firstNoteStatus = app.staticTexts["Setup required"]
        XCTAssertTrue(firstNoteStatus.waitForExistence(timeout: 5))
        XCTAssertLessThan(notesToolbar.frame.midY, firstNoteStatus.frame.midY)
    }

    func testPartialScrollSpringsBackWithoutLeavingEmptySpace() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments
        app.launch()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 10))
        app.buttons["watch-stop"].tap()

        let recordButton = app.buttons["watch-record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        let restingMidY = recordButton.frame.midY
        let window = app.windows.firstMatch
        let historyHeading = app.staticTexts["watch-previous-notes"]
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            .press(forDuration: 0.1,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))

        let settledOnFullPage = expectation(for: NSPredicate { _, _ in
            let captureIsFullPage = abs(recordButton.frame.midY - restingMidY) <= 2
                && (!historyHeading.exists || historyHeading.frame.minY >= window.frame.maxY - 2)
            let historyIsFullPage = historyHeading.exists
                && recordButton.frame.maxY <= window.frame.minY + 2
                && window.frame.intersects(historyHeading.frame)
            return captureIsFullPage || historyIsFullPage
        }, evaluatedWith: nil)
        wait(for: [settledOnFullPage], timeout: 5)
    }

    func testCaptureAndHistorySettleOnOppositeFullPages() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments
        app.launch()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 10))
        app.buttons["watch-stop"].tap()
        let recordButton = app.buttons["watch-record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        let restingMidY = recordButton.frame.midY
        let window = app.windows.firstMatch
        let historyHeading = app.staticTexts["watch-previous-notes"]

        app.swipeUp()
        let historyIsFullPage = expectation(for: NSPredicate { _, _ in
            historyHeading.exists
                && recordButton.frame.maxY <= window.frame.minY + 2
                && window.frame.intersects(historyHeading.frame)
        }, evaluatedWith: nil)
        wait(for: [historyIsFullPage], timeout: 5)

        app.swipeDown()
        let captureIsFullPage = expectation(for: NSPredicate { _, _ in
            abs(recordButton.frame.midY - restingMidY) <= 2
                && (!historyHeading.exists || historyHeading.frame.minY >= window.frame.maxY - 2)
        }, evaluatedWith: nil)
        wait(for: [captureIsFullPage], timeout: 5)
    }

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
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["No Notes yet"].waitForExistence(timeout: 5))
    }

    func testForegroundRestoresCaptureAndDoesNotRestartAfterStop() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments
        app.launch()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["No Notes yet"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 5))
        app.swipeDown()
        app.buttons["watch-stop"].tap()
        XCTAssertTrue(app.buttons["watch-record"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["watch-record"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["watch-stop"].exists)
    }
}
