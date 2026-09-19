import XCTest
@testable import WhimIPhone

final class TimelineFormatTests: XCTestCase {
    func testDurationMatchesCurrentUI() {
        XCTAssertEqual(TimelineFormat.duration(seconds: -1), "0:00")
        XCTAssertEqual(TimelineFormat.duration(seconds: 65.9), "1:05")
        XCTAssertEqual(TimelineFormat.duration(seconds: 300), "5:00")
    }
}

final class HistorySheetMotionTests: XCTestCase {
    func testBreakpointZeroHidesTheEntireSheetBelowTheSafeArea() {
        XCTAssertEqual(
            HistorySheetMotion.offset(
                isOpen: false,
                openingTranslation: 0,
                closingTranslation: 0,
                height: 800,
                safeAreaBottom: 34
            ),
            834
        )
        XCTAssertEqual(
            HistorySheetMotion.offset(
                isOpen: true,
                openingTranslation: 0,
                closingTranslation: 0,
                height: 800,
                safeAreaBottom: 34
            ),
            0
        )
    }

    func testOpeningDragGainsResistanceBeforeTheSheetSettlesOpen() {
        let first = HistorySheetMotion.openingReveal(translation: -100, height: 800)
        let second = HistorySheetMotion.openingReveal(translation: -200, height: 800)

        XCTAssertGreaterThan(first, 0)
        XCTAssertLessThan(first, 100)
        XCTAssertGreaterThan(second, first)
        XCTAssertLessThan(second - first, first)
    }
}

final class HistoryScrollDismissalTests: XCTestCase {
    func testDownwardDragFromTopMovesSheetWithFinger() {
        XCTAssertEqual(
            HistoryScrollDismissal.dragOffset(
                gestureBeganAtTop: true,
                translation: 120
            ),
            120
        )
        XCTAssertEqual(
            HistoryScrollDismissal.dragOffset(
                gestureBeganAtTop: false,
                translation: 120
            ),
            0
        )
        XCTAssertEqual(
            HistoryScrollDismissal.dragOffset(
                gestureBeganAtTop: true,
                translation: -40
            ),
            0
        )
    }

    func testDragThatOnlyReachesTheTopDoesNotDismiss() {
        XCTAssertFalse(
            HistoryScrollDismissal.shouldDismiss(
                gestureBeganAtTop: false,
                translation: 180,
                predictedTranslation: 300
            )
        )
    }

    func testNewDownwardDragFromTheTopDismissesAfterTheThreshold() {
        XCTAssertFalse(
            HistoryScrollDismissal.shouldDismiss(
                gestureBeganAtTop: true,
                translation: 40,
                predictedTranslation: 80
            )
        )
        XCTAssertTrue(
            HistoryScrollDismissal.shouldDismiss(
                gestureBeganAtTop: true,
                translation: 120,
                predictedTranslation: 220
            )
        )
    }
}
