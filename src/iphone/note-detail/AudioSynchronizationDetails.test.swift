import Foundation
import XCTest
import WhimCore
import WhimIPhone

final class AudioSynchronizationDetailsTests: XCTestCase {
    private func details(status: AudioSynchronization.Status = .failed, reason: String? = nil,
                         error: SynchronizationSystemError? = nil) -> AudioSynchronizationDetails {
        let failure = reason.map { AudioSynchronizationFailure(reason: $0, observedAt: Date(timeIntervalSince1970: 1000), systemError: error) }
        let note = Note(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Private title",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false, audioURL: URL(fileURLWithPath: "/private/audio.m4a"),
            audioSynchronization: .init(status: status, transferCount: 3, lastFailure: failure))
        return .init(note: .init(note: note, hasLocalAudio: false))
    }
    func testWaitingAndLegacyFailureDoNotInventACause() {
        let waiting = details(status: .waiting)
        XCTAssertEqual(waiting.cause, "The audio has not arrived on this iPhone.")
        XCTAssertFalse(waiting.cause?.contains("unreadable") == true)
        XCTAssertTrue(details().cause?.contains("could not synchronize") == true)
        XCTAssertTrue(details().technicalRows.contains(.init("Last failure", "Not reported")))
    }
    func testReceivedAudioAndUnavailableSourceGiveDifferentRecoveryActions() {
        let unreadable = details(reason: "unreadableReceivedAudio")
        XCTAssertTrue(unreadable.cause?.contains("could not read a playable copy") == true)
        XCTAssertTrue(unreadable.recovery?.contains("Retry sync") == true)
        for reason in ["missingNote", "missingAudio", "expiredAudio"] {
            let unavailable = details(reason: reason)
            XCTAssertTrue(unavailable.recovery?.contains("may not be recoverable") == true, reason)
        }
        XCTAssertTrue(details(reason: "sourceUnavailable").cause?.contains("could not supply") == true)
        XCTAssertTrue(details(reason: "sourceNotReady").cause?.contains("not ready") == true)
    }
    func testStorageAdviceRequiresAnObservedStorageErrorAndDetailsAreSafe() {
        let error = SynchronizationSystemError(error: NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.ENOSPC.rawValue),
            userInfo: [NSLocalizedDescriptionKey: "token=secret"]), observedAt: Date())
        let full = details(reason: "localSaveFailed", error: error)
        XCTAssertTrue(full.recovery?.contains("Free up storage") == true)
        let unknown = details(reason: "localSaveFailed")
        XCTAssertFalse(unknown.recovery?.contains("Free up storage") == true)
        XCTAssertTrue(full.technicalRows.contains(.init("Transfers in this cycle", "3 of 3")))
        XCTAssertFalse(full.technicalRows.contains { $0.value.contains("secret") || $0.value.contains("Private title") || $0.value.contains("/private") })
    }
}
