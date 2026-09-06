import Foundation

public enum TranscriptionError: Error, Sendable, Equatable {
    case unavailable
    case notAuthorized
    case recognitionFailed
}

public protocol Transcriber: Sendable {
    func transcribe(audioAt url: URL, locale: Locale) async throws -> String
}

/// Used by watchOS composition, where v1 intentionally never starts Speech recognition.
public struct TimestampOnlyTranscriber: Transcriber {
    public init() {}

    public func transcribe(audioAt url: URL, locale: Locale) async throws -> String {
        throw TranscriptionError.unavailable
    }
}
