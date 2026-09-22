import Foundation

/// User-facing failure without raw system errors, secrets, or Note content.
public struct ActionableFailure: Equatable, Sendable {
    public enum Operation: Sendable { case preparation, capture, history, settings, synchronization, request, playback, maintenance }
    public enum Action: Sendable { case retry, microphoneSettings, liveActivitySettings, storageInstructions, configureWebhook }
    public let message: String
    public let action: Action
    public let operation: Operation
    public let blocksCapture: Bool

    public init(_ error: any Error, operation: Operation) {
        self.operation = operation
        let nsError = error as NSError
        if operation == .playback {
            if (error as? WhimServiceError) == .audioUnavailable {
                message = "This Note’s audio file is missing or unreadable on this device. Unlock your device and try again."
            } else if (error as? WhimServiceError) == .recordingActive {
                message = "Stop the current recording before playing this Note."
            } else {
                message = "The audio player could not open this Note. Try playback again."
            }
            action = .retry; blocksCapture = false
        } else if (error as? POSIXError)?.code == .ENOSPC || (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError) {
            message = "Your device needs more free storage to save audio."
            action = .storageInstructions; blocksCapture = true
        } else if error is RecordingActivityError {
            message = "Enable Live Activities for Whim in Settings to record, then try again."
            action = .liveActivitySettings; blocksCapture = true
        } else if (error as? WhimServiceError) == .permissionDenied {
            message = "Microphone access is required to capture a Note. Allow Whim access in Settings."
            action = .microphoneSettings; blocksCapture = true
        } else if error is ConfigurationTestError || { if case WhimServiceError.invalidConfiguration = error { true } else { false } }() {
            message = "Set up a working webhook to deliver your saved Notes."
            action = .configureWebhook; blocksCapture = false
        } else {
            action = .retry
            blocksCapture = operation == .preparation
            switch operation {
            case .playback: message = "The audio player could not open this Note. Try playback again."
            case .maintenance: message = "Background recovery or device synchronization could not finish. Saved Notes can still be browsed and played on this device."
            case .preparation: message = "Whim could not prepare recording. Please try again."
            case .capture: message = "Whim could not complete the recording action. Please try again."
            case .history: message = "Previous Notes could not be loaded. Recording is still available."
            case .settings: message = "Settings could not be loaded. Recording is still available."
            case .request: message = "Whim could not complete this action. Refresh, then try the action again."
            case .synchronization: message = "Device synchronization could not finish. Recording is still available."
            }
        }
    }

    public var actionLabel: String {
        switch action {
        case .microphoneSettings, .liveActivitySettings: return "Open Settings"
        case .storageInstructions: return "Show instructions"
        case .configureWebhook: return "Configure webhook"
        case .retry:
            switch operation {
            case .preparation, .capture: return "Try again"
            case .history: return "Retry history"
            case .settings: return "Retry settings"
            case .synchronization: return "Retry sync"
            case .request: return "Refresh"
            case .playback: return "Try playback again"
            case .maintenance: return "Retry background tasks"
            }
        }
    }
}
