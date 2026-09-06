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
        var isExecuting: Bool
    }

    private let clock: any Clock
    private let sleeper: any DeliverySleeper
    private var pending: [NoteID: Pending] = [:]

    public init(clock: any Clock = SystemClock(), sleeper: any DeliverySleeper = SystemDeliverySleeper()) {
        self.clock = clock
        self.sleeper = sleeper
    }

    public func schedule(noteID: NoteID, earliest: Date,
                         operation: @escaping @Sendable () async throws -> Void,
                         onFailure: @escaping @Sendable (any Error) async -> Void) {
        if let existing = pending[noteID], !existing.isExecuting, existing.earliest <= earliest { return }
        pending[noteID]?.task.cancel()

        let token = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(noteID: noteID, earliest: earliest, token: token,
                operation: operation, onFailure: onFailure)
        }
        pending[noteID] = Pending(earliest: earliest, token: token, task: task, isExecuting: false)
    }

    public func cancel(noteID: NoteID) async {
        guard let task = pending.removeValue(forKey: noteID)?.task else { return }
        task.cancel()
        await task.value
    }

    private func run(noteID: NoteID, earliest: Date, token: UUID,
                     operation: @escaping @Sendable () async throws -> Void,
                     onFailure: @escaping @Sendable (any Error) async -> Void) async {
        do {
            try await sleeper.sleep(for: max(0, earliest.timeIntervalSince(clock.now)))
        } catch {
            remove(noteID: noteID, token: token)
            if !(error is CancellationError) { await onFailure(error) }
            return
        }
        guard !Task.isCancelled else {
            remove(noteID: noteID, token: token)
            return
        }
        guard markExecuting(noteID: noteID, token: token) else { return }
        var attempts = 0
        while !Task.isCancelled, pending[noteID]?.token == token {
            do {
                attempts += 1
                try await operation()
                remove(noteID: noteID, token: token)
                return
            } catch {
                guard !Task.isCancelled else {
                    remove(noteID: noteID, token: token)
                    return
                }
                guard attempts < DeliveryTimeouts.maximumScheduledOperationAttempts else {
                    remove(noteID: noteID, token: token)
                    await onFailure(error)
                    return
                }
                do {
                    try await sleeper.sleep(for: DeliveryTimeouts.scheduledOperationRetry)
                } catch {
                    remove(noteID: noteID, token: token)
                    if !(error is CancellationError) { await onFailure(error) }
                    return
                }
            }
        }
    }

    private func remove(noteID: NoteID, token: UUID) {
        if pending[noteID]?.token == token { pending[noteID] = nil }
    }

    private func markExecuting(noteID: NoteID, token: UUID) -> Bool {
        guard var current = pending[noteID], current.token == token else { return false }
        current.isExecuting = true
        pending[noteID] = current
        return true
    }
}
