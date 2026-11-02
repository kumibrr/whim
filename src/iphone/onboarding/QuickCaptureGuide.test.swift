import XCTest
@testable import WhimIPhone

final class QuickCaptureGuideTests: XCTestCase {
    func testActionButtonPagesUseTheirMatchingDemo() {
        XCTAssertEqual(QuickCaptureGuide.mediaName(route: .actionButton, isWatch: false, page: 0), "action-button-preview")
        XCTAssertEqual(QuickCaptureGuide.mediaName(route: .actionButton, isWatch: false, page: 1), "action-button-setup")
        XCTAssertNil(QuickCaptureGuide.mediaName(route: .actionButton, isWatch: false, page: 2))
        XCTAssertNil(QuickCaptureGuide.mediaName(route: .lockScreen, isWatch: false, page: 0))
        XCTAssertNil(QuickCaptureGuide.mediaName(route: .actionButton, isWatch: true, page: 0))
        XCTAssertNil(QuickCaptureGuide.mediaName(route: .actionButton, isWatch: false, page: 3))
    }


    func testUpgradeGuideOnlyAppearsForCompletedOnboardingWithoutAcknowledgement() {
        XCTAssertTrue(QuickCaptureGuide.needsUpgradeGuide(onboardingCompleted: true, acknowledged: false))
        XCTAssertFalse(QuickCaptureGuide.needsUpgradeGuide(onboardingCompleted: false, acknowledged: false))
        XCTAssertFalse(QuickCaptureGuide.needsUpgradeGuide(onboardingCompleted: true, acknowledged: true))
    }

    func testSavedWatchStepResumesAtPhoneSetupWhileWatchOnboardingIsHidden() {
        XCTAssertEqual(QuickCaptureGuide.onboardingStep(saved: 4, setupOnly: false), 3)
        XCTAssertEqual(QuickCaptureGuide.onboardingStep(saved: 4, setupOnly: true), 3)
        XCTAssertEqual(QuickCaptureGuide.onboardingStep(saved: 1, setupOnly: false), 1)
    }

    func testPhoneSetupCompletesEvenWhenWatchIsPaired() {
        XCTAssertNil(QuickCaptureGuide.nextSetupStep(after: 3, hasPairedWatch: true))
        XCTAssertNil(QuickCaptureGuide.nextSetupStep(after: 3, hasPairedWatch: false))
        XCTAssertNil(QuickCaptureGuide.nextSetupStep(after: 4, hasPairedWatch: true))
    }

    func testActionButtonPhonesReceiveTheGuidedShortcutRoute() {
        for model in ["iPhone16,1", "iPhone16,2", "iPhone17,1", "iPhone17,5", "iPhone18,1", "iPhone18,4", "iPhone18,5", "iPhone19,2", "iPhone19,3"] {
            XCTAssertEqual(QuickCaptureGuide.route(for: model), .actionButton, model)
        }
    }
    func testOlderAndUnknownHardwareUseUniversallyAvailableControls() {
        for model in ["iPhone15,4", "iPhone15,5", "iPhone14,6", "iPad16,1", "unknown", "iPhone99,1"] {
            XCTAssertEqual(QuickCaptureGuide.route(for: model), .lockScreen, model)
        }
    }
}
