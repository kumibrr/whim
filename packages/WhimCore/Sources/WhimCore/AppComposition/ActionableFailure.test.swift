import Foundation
import XCTest
@testable import WhimCore

final class ActionableFailureTests: XCTestCase {
    func testUnavailableLiveActivityExplainsSettingsRecovery() {
        let failure = ActionableFailure(RecordingActivityError.unavailable, operation: .capture)
        XCTAssertEqual(failure.message, "Enable Live Activities for Whim in Settings to record, then try again.")
        XCTAssertEqual(failure.actionLabel, "Open Settings")
        XCTAssertTrue(failure.blocksCapture)
    }

    func testPlaybackFailureExplainsLocalAudioAndOffersPlaybackRetry() {
        let missing = ActionableFailure(WhimServiceError.audioUnavailable, operation: .playback)
        XCTAssertTrue(missing.message.contains("audio file"))
        XCTAssertTrue(missing.message.contains("this device"))
        XCTAssertEqual(missing.actionLabel, "Try playback again")
        let unavailable = ActionableFailure(NSError(domain: "private", code: 1), operation: .playback)
        XCTAssertTrue(unavailable.message.contains("audio player"))
        XCTAssertFalse(unavailable.message.contains("Refresh"))
    }
    func testPermissionAndStorageFailuresOfferResolvingActions() {
        let denied = ActionableFailure(WhimServiceError.permissionDenied, operation: .capture)
        XCTAssertEqual(denied.action, .microphoneSettings)
        XCTAssertTrue(denied.blocksCapture)
        let full = ActionableFailure(POSIXError(.ENOSPC), operation: .preparation)
        XCTAssertEqual(full.action, .storageInstructions)
        XCTAssertTrue(full.message.contains("storage"))
        XCTAssertEqual(ActionableFailure(CocoaError(.fileWriteOutOfSpace), operation: .capture).action, .storageInstructions)
    }
    func testAuxiliaryFailureIsRetryableWithoutBlockingCaptureOrLeakingDetails() {
        let error = NSError(domain: "secret", code: 1, userInfo: [NSLocalizedDescriptionKey: "private title"])
        let issue = ActionableFailure(error, operation: .history)
        XCTAssertEqual(issue.action, .retry)
        XCTAssertEqual(issue.actionLabel, "Retry history")
        XCTAssertFalse(issue.blocksCapture)
        XCTAssertFalse(issue.message.contains("secret"))
        XCTAssertFalse(issue.message.contains("private"))
    }
}
