import Foundation

/// The activity renders this snapshot directly; microphone data never includes audio samples.
public struct RecordingActivityContent: Codable, Hashable, Sendable {
    public let startedAt: Date
    public let power: Float
    public let tone: Float

    public init(startedAt: Date, power: Float = -160, tone: Float = 0) {
        self.startedAt = startedAt
        self.power = power.isFinite ? max(-160, min(0, power)) : -160
        self.tone = tone.isFinite ? max(0, min(1, tone)) : 0
    }

    private enum CodingKeys: String, CodingKey { case startedAt, power, tone }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(startedAt: try values.decode(Date.self, forKey: .startedAt),
            power: try values.decodeIfPresent(Float.self, forKey: .power) ?? -160,
            tone: try values.decodeIfPresent(Float.self, forKey: .tone) ?? 0)
    }
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

public struct RecordingActivityAttributes: ActivityAttributes {
    public typealias ContentState = RecordingActivityContent
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
    public func update(sessionID: RecordingSessionID, signal: RecordingSignal) async {
        for activity in Activity<RecordingActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
            let content = activity.content
            await activity.update(ActivityContent(
                state: .init(startedAt: content.state.startedAt, power: signal.peakPowerDBFS, tone: signal.tone), staleDate: content.staleDate))
        }
    }
    public func end(_ sessionID: RecordingSessionID) async {
        for activity in Activity<RecordingActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
#endif
