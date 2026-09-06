import Foundation

public protocol DeliverySleeper: Sendable {
    func sleep(for interval: TimeInterval) async throws
}

public struct SystemDeliverySleeper: DeliverySleeper {
    public init() {}

    public func sleep(for interval: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(max(0, interval)))
    }
}

/// Provides a bounded foreground retry opportunity. Operating-system background
/// opportunities can call DeliveryService independently without changing this seam.
public actor InProcessDeliveryScheduler: DeliveryScheduler {
    private struct Pending: Sendable {
        let earliest: Date
        let token: UUID
        let task: Task<Void, Never>
    }

    private let clock: any Clock
    private let sleeper: any DeliverySleeper
    private var pending: [NoteID: Pending] = [:]

    public init(clock: any Clock = SystemClock(), sleeper: any DeliverySleeper = SystemDeliverySleeper()) {
        self.clock = clock
        self.sleeper = sleeper
    }

    public func schedule(noteID: NoteID, earliest: Date,
                         operation: @escaping @Sendable () async -> Void) {
        if let existing = pending[noteID], existing.earliest <= earliest { return }
        pending[noteID]?.task.cancel()

        let token = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(noteID: noteID, earliest: earliest, token: token, operation: operation)
        }
        pending[noteID] = Pending(earliest: earliest, token: token, task: task)
    }

    private func run(noteID: NoteID, earliest: Date, token: UUID,
                     operation: @escaping @Sendable () async -> Void) async {
        do {
            try await sleeper.sleep(for: max(0, earliest.timeIntervalSince(clock.now)))
        } catch {
            remove(noteID: noteID, token: token)
            return
        }
        guard !Task.isCancelled, pending[noteID]?.token == token else { return }
        pending[noteID] = nil
        await operation()
    }

    private func remove(noteID: NoteID, token: UUID) {
        if pending[noteID]?.token == token { pending[noteID] = nil }
    }
}
