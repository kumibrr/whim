import Foundation
import WhimCore

public struct AudioSynchronizationDetails: Sendable {
    public let cause: String?
    public let recovery: String?
    public let technicalRows: [SynchronizationTechnicalRow]
    public init(note: NoteDetailProjection) {
        let state = note.audioSynchronization
        if let failure = state?.lastFailure {
            cause = Self.failureCause(failure)
            recovery = Self.failureRecovery(failure)
        } else if let state {
            cause = state.status == .failed
                ? "Whim could not synchronize a playable copy of this Note’s audio."
                : "The audio has not arrived on this iPhone."
            recovery = "Open Whim on your Watch and check playback there, then use Retry sync when both devices are available."
        } else { cause = nil; recovery = nil }
        var rows: [SynchronizationTechnicalRow] = [
            .init("Audio synchronization state", state?.status.rawValue.capitalized ?? "Available"),
            .init("Transfers in this cycle", state.map { "\($0.transferCount) of \(AudioSynchronization.maximumTransfers)" } ?? "Completed"),
            .init("Note ID", note.id),
            .init("Current request ID", state?.requestID?.uuidString.lowercased() ?? "Not reported")
        ]
        if let failure = state?.lastFailure {
            rows += [.init("Last failure", Self.failureCause(failure)),
                .init("Failure observed", TimelineFormat.date(failure.observedAt)),
                .init("Failure request ID", failure.requestID?.uuidString.lowercased() ?? "Not reported")]
            rows += synchronizationErrorRows(failure.systemError, prefix: "Audio save")
        } else { rows.append(.init("Last failure", "Not reported")) }
        technicalRows = rows
    }
    public static func failureCause(_ failure: AudioSynchronizationFailure) -> String {
        switch failure.reason {
        case "unreadableReceivedAudio": "This iPhone could not read a playable copy of the audio received from Watch."
        case "missingNote": "Whim on Watch could not find this Note."
        case "missingAudio": "Whim on Watch could not find this Note’s audio file."
        case "expiredAudio": "This Note’s audio has expired on Watch."
        case "unreadableAudio": "Whim on Watch could not read a playable copy of this Note’s audio."
        case "sourceNotReady": "The Watch audio is not ready to synchronize."
        case "sourceUnavailable": "The Watch could not supply this Note’s audio."
        case "localSaveFailed": failure.systemError?.category == "storageFull"
            ? "This iPhone could not save the audio because storage is full."
            : "This iPhone could not save a playable local copy of the audio."
        default: "Whim could not determine why the audio failed to synchronize."
        }
    }
    public static func failureRecovery(_ failure: AudioSynchronizationFailure) -> String {
        switch failure.reason {
        case "missingNote", "missingAudio", "expiredAudio":
            "Check for a playable copy on your Watch or at your Workflow destination. Audio missing from Watch may not be recoverable with Retry sync."
        case "sourceUnavailable":
            "Open Whim on Watch and check whether the Note plays there. If the source is missing, another copy may not be recoverable with Retry sync."
        case "localSaveFailed" where failure.systemError?.category == "storageFull":
            "Free up storage on this iPhone, then use Retry sync. Keep the Watch copy until synchronization finishes."
        case "localSaveFailed":
            "Keep the Watch copy, reopen Whim on this iPhone, then use Retry sync."
        default:
            "Open Whim on Watch and check playback there, then use Retry sync. Keep both devices nearby while Whim requests another copy."
        }
    }
}
