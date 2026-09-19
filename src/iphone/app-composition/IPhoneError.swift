import Foundation
import WhimCore

public struct IPhoneError: Error, Equatable, Sendable {
    public let message: String
    public init(_ error: any Error) {
        switch error {
        case WhimServiceError.recordingActive: message = "Stop recording before playing a Note."
        case WhimServiceError.audioUnavailable: message = "This Note's audio is unavailable."
        case WhimServiceError.permissionDenied: message = "Microphone access is required. Open Settings to allow access."
        case WhimServiceError.invalidConfiguration: message = "Enter a valid webhook configuration."
        case WhimServiceError.invalidIdentifier: message = "The identifier is invalid."
        case WhimServiceError.setupRequired: message = "Whim setup is required."
        case ConfigurationTestError.missingConfiguration: message = "Configure a webhook before testing it."
        case WhimStoreError.missingNote: message = "The Note no longer exists."
        case WhimStoreError.notEligible: message = "The Note is not eligible for this command."
        default: message = "Whim could not complete the request."
        }
    }
}
