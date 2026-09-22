import XCTest

@MainActor final class ComplicationLaunchUITests: XCTestCase {
    // watchOS 27 Simulator rejects external URL dispatch (LSApplicationWorkspace error 115).
    // Supply the same launch context at the app boundary; warm reentry is covered by WatchModel integration tests.
    func testComplicationLaunchContextStartsAndSavesOneNote() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments + ["-WhimCaptureURL", "whim://record"]
        app.launch()
        XCTAssertTrue(app.buttons["watch-stop"].waitForExistence(timeout: 15))
        app.buttons["watch-stop"].tap()
        XCTAssertTrue(app.buttons["watch-record"].waitForExistence(timeout: 10))
        app.swipeUp()
        let notes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "watch-note-"))
        XCTAssertTrue(notes.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(notes.count, 1)
    }
    func testUnrecognizedLaunchContextDoesNotStartCapture() {
        let app = XCUIApplication()
        app.launchArguments = WatchUITestConfiguration.arguments + ["-WhimCaptureURL", "other://record"]
        app.launch()
        XCTAssertTrue(app.buttons["watch-record"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["watch-stop"].exists)
    }
}
