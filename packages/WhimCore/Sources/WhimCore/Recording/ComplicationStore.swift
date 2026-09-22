import Foundation

public struct ComplicationStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> ComplicationSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return .idle }
        return try JSONDecoder().decode(ComplicationSnapshot.self, from: Data(contentsOf: url))
    }
    public func save(_ snapshot: ComplicationSnapshot) throws -> Bool {
        if (try? load()) == snapshot { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        return true
    }
}

public actor ComplicationPublisher {
    private let client: any WhimClient
    private let store: ComplicationStore
    private let reload: @Sendable () -> Void
    public init(client: any WhimClient, store: ComplicationStore, reload: @escaping @Sendable () -> Void = {}) {
        self.client = client; self.store = store; self.reload = reload
    }
    public func refresh() async throws {
        let recording = try await client.activeRecording()
        let failed = try await client.listNotes(filter: .failed)
        if try store.save(.init(recording: recording, hasFailedNotes: !failed.isEmpty)) { reload() }
    }
    public nonisolated func observe() -> Task<Void, Never> {
        let events = client.events()
        return Task {
            try? await refresh()
            for await event in events {
                if Task.isCancelled { return }
                switch event.type {
                case .recordingStarted, .recordingStopped, .recordingDiscarded, .noteChanged, .noteDeleted, .notesReset:
                    try? await refresh()
                default: break
                }
            }
        }
    }
}
