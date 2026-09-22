import Foundation

public enum RecordingActivityError: Error, Sendable { case unavailable }

public protocol RecordingActivitySystem: Sendable {
    func sessions() async -> [RecordingSessionID]
    func request(_ recording: RecordingSnapshot) async throws
    func end(_ sessionID: RecordingSessionID) async
}

public actor LiveActivityAdapter: RecordingActivityManaging {
    private let system: any RecordingActivitySystem
    public init(system: any RecordingActivitySystem) { self.system = system }
    public func start(_ recording: RecordingSnapshot) async throws {
        await reconcile(activeSessionID: recording.sessionID)
        guard !(await system.sessions()).contains(recording.sessionID) else { return }
        try await system.request(recording)
    }
    public func end(sessionID: RecordingSessionID) async { await system.end(sessionID) }
    public func reconcile(activeSessionID: RecordingSessionID?) async {
        for session in await system.sessions() where session != activeSessionID { await system.end(session) }
    }
}
