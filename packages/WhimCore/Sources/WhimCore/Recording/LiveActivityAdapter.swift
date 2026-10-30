import Foundation

public enum RecordingActivityError: Error, Sendable { case unavailable }

public protocol RecordingActivitySystem: Sendable {
    func sessions() async -> [RecordingSessionID]
    func request(_ recording: RecordingSnapshot) async throws
    func update(sessionID: RecordingSessionID, signal: RecordingSignal) async
    func end(_ sessionID: RecordingSessionID) async
}

public actor LiveActivityAdapter: RecordingActivityManaging {
    private let system: any RecordingActivitySystem
    private let clock: any Clock
    private var lastPublication: [RecordingSessionID: (date: Date, signal: RecordingSignal)] = [:]
    public init(system: any RecordingActivitySystem, clock: any Clock = SystemClock()) {
        self.system = system
        self.clock = clock
    }
    public func start(_ recording: RecordingSnapshot) async throws {
        await reconcile(activeSessionID: recording.sessionID)
        guard !(await system.sessions()).contains(recording.sessionID) else { return }
        try await system.request(recording)
    }
    public func update(sessionID: RecordingSessionID, signal: RecordingSignal) async {
        guard await system.sessions().contains(sessionID) else { return }
        let now = clock.now
        if let last = lastPublication[sessionID],
           last.signal == signal || now.timeIntervalSince(last.date) < 0.2 { return }
        lastPublication[sessionID] = (now, signal)
        await system.update(sessionID: sessionID, signal: signal)
    }
    public func end(sessionID: RecordingSessionID) async {
        lastPublication[sessionID] = nil
        await system.end(sessionID)
    }
    public func reconcile(activeSessionID: RecordingSessionID?) async {
        for session in await system.sessions() where session != activeSessionID { await end(sessionID: session) }
    }
}
