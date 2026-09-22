#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

public struct RecordingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public let startedAt: Date
        public init(startedAt: Date) { self.startedAt = startedAt }
    }
    public let sessionID: RecordingSessionID
    public init(sessionID: RecordingSessionID) { self.sessionID = sessionID }
}

public struct ActivityKitRecordingSystem: RecordingActivitySystem {
    public init() {}
    public func sessions() async -> [RecordingSessionID] {
        Activity<RecordingActivityAttributes>.activities.map { $0.attributes.sessionID }
    }
    public func request(_ recording: RecordingSnapshot) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw RecordingActivityError.unavailable }
        _ = try Activity<RecordingActivityAttributes>.request(
            attributes: RecordingActivityAttributes(sessionID: recording.sessionID),
            content: ActivityContent(state: .init(startedAt: recording.createdAt), staleDate: recording.createdAt.addingTimeInterval(300)),
            pushType: nil)
    }
    public func end(_ sessionID: RecordingSessionID) async {
        for activity in Activity<RecordingActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
#endif
