import XCTest
import WhimCore
@testable import WhimIPhone
final class IPhoneErrorTests: XCTestCase {
    func testUnknownErrorsNeverExposePrivateDetails() {
        let error = NSError(domain: "https://private.example?token=secret", code: 500, userInfo: [NSLocalizedDescriptionKey: "private audio title"])
        XCTAssertEqual(IPhoneError(error).message, "Whim could not complete the request.")
    }
    func testMissingAudioAndNoteHaveActionableCopy() {
        XCTAssertEqual(IPhoneError(WhimServiceError.audioUnavailable).message, "This Note's audio is unavailable.")
        XCTAssertEqual(IPhoneError(WhimStoreError.missingNote).message, "The Note no longer exists.")
    }
}
