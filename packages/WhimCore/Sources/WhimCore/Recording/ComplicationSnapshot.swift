import Foundation

public struct ComplicationSnapshot: Codable, Equatable, Sendable {
    public let recording: RecordingProjection?
    public let hasFailedNotes: Bool
    public init(recording: RecordingProjection?, hasFailedNotes: Bool) {
        self.recording = recording; self.hasFailedNotes = hasFailedNotes
    }
    public func activeRecording(at date: Date) -> RecordingProjection? {
        guard let recording, date < recording.createdAt.addingTimeInterval(recording.maximumDurationSeconds) else { return nil }
        return recording
    }
    public static let idle = ComplicationSnapshot(recording: nil, hasFailedNotes: false)
}
