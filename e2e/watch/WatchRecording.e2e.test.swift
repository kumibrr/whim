import XCTest

@MainActor
final class WatchRecordingUITests: XCTestCase {
    // Exercise the controls targeted by the primary hand gesture. Actual finger
    // recognition is covered in physical/watch-capture.e2e.test.md: watchOS 27
    // simulator gesture injection also fails for a plain primary-action Button.
    func testCaptureControlStopsStartsAndSavesWithoutScrolling() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments
        app.launch()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 15))

        app.buttons["watch-stop"].tap()
        let record = app.buttons["watch-record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertTrue(record.isHittable)

        record.tap()
        let stop = app.buttons["watch-stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        XCTAssertTrue(stop.isHittable)

        stop.tap()
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertTrue(record.isHittable)
        app.swipeUp()
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "watch-note-")
        ).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "watch-note-")
        ).count, 2)
    }

    func testLaunchCapturesAndStopSavesLocallyWithoutConfiguration() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments
        app.launch()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["watch-waveform"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["watch-recorder"].exists)
        let historyHeading = app.navigationBars["Previous Notes"]
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
        let firstNote = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "watch-note-")
        ).firstMatch
        XCTAssertTrue(firstNote.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(firstNote.frame.minY - notesToolbar.frame.maxY, 44)
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
        let historyHeading = app.navigationBars["Previous Notes"]
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
        let historyHeading = app.navigationBars["Previous Notes"]

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

    func testDiscardImmediatelyLeavesNoNote() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments
        app.launch()
        XCTAssertTrue(app.buttons["watch-discard"].waitForExistence(timeout: 10))
        let discard = app.buttons["watch-discard"]
        XCTAssertGreaterThanOrEqual(discard.frame.width, 100)
        XCTAssertGreaterThanOrEqual(discard.frame.height, 44)
        // The controls must remain adjacent so Discard can morph from the capture button.
        if #available(watchOS 26, *) {
            XCTAssertLessThanOrEqual(discard.frame.minY - app.buttons["watch-stop"].frame.maxY, 12)
        }
        discard.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["watch-record"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Discard Recording"].exists)
        app.buttons["watch-record"].tap()
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["watch-record"].exists)
        discard.tap()
        XCTAssertTrue(app.buttons["watch-record"].waitForExistence(timeout: 5))
        XCTAssertFalse(discard.exists)
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
