import Foundation

public struct MaintenanceService: Sendable {
    private let store: any WhimStore
    private let files: any AudioFileManaging
    private let preferences: any PreferenceStoring
    private let background: any BackgroundScheduling
    private let device: AttemptDevice

    public init(store: any WhimStore, files: any AudioFileManaging, preferences: any PreferenceStoring,
                background: any BackgroundScheduling = NoBackgroundScheduler(), device: AttemptDevice = .iphone) {
        self.store = store; self.files = files; self.preferences = preferences
        self.background = background; self.device = device
    }

    @discardableResult
    public func run(now: Date, preserving noteIDs: Set<NoteID> = []) async throws -> [NoteID] {
        let policy = try await preferences.load().retentionPolicy
        var expired: [NoteID] = []
        var nextWork: BackgroundWork?
        for projection in try await store.listNotes(filter: .sent) {
            try Task.checkCancellation()
            guard let ownership = try files.claimOwnership(noteID: projection.id) else { continue }
            defer { withExtendedLifetime(ownership) {} }
            guard let note = try await store.note(id: projection.id),
                  let receipt = note.delivery.receipt, !note.requiresReview else { continue }
            let deadline = policy == .never ? nil : receipt.receivedAt.addingTimeInterval(Double(policy.rawValue) * 86_400)
            if !noteIDs.contains(note.id), note.audioExpiredAt != nil || deadline.map({ $0 <= now }) == true {
                if try await store.markAudioExpired(noteID: note.id, at: now) {
                    try files.delete(noteID: note.id)
                    if note.audioExpiredAt == nil { expired.append(note.id) }
                }
            } else if note.audioExpiredAt == nil, note.localError == nil {
                try files.makeDeliveredProtectionStrict(noteID: note.id)
                if !noteIDs.contains(note.id), let deadline,
                   nextWork == nil || deadline < nextWork!.earliest {
                    nextWork = BackgroundWork(earliest: max(now, deadline), requiresNetwork: false)
                }
            }
        }
        for projection in try await store.listNotes(filter: .all) {
            try Task.checkCancellation()
            guard projection.workflowError == nil,
                  projection.status == .queued || projection.status == .sending else { continue }
            guard let note = try await store.note(id: projection.id), note.isDeliveryEligible,
                  let revision = try await store.configurationRevision(for: note.id) else { continue }
            let failures = note.delivery.failedAttempts.filter {
                $0.attempt.device == device && $0.attempt.configurationRevisionID == revision.id
                    && $0.attempt.retryCycle == note.delivery.currentRetryCycle
            }.sorted { ($0.failedAt, $0.attempt.id.rawValue.uuidString) < ($1.failedAt, $1.attempt.id.rawValue.uuidString) }
            guard failures.count < RetryPolicy.maximumFailedAttempts,
                  !failures.contains(where: { RetryPolicy.classification(for: $0.reason) == .permanent }) else { continue }
            var earliest = now
            if let last = failures.last,
               let retry = RetryPolicy.nextEligibility(after: failures.count, now: last.failedAt,
                                                       retryAfter: last.retryAfter) {
                earliest = max(earliest, retry)
            }
            if let horizon = note.delivery.activeAttempts.filter({ $0.device == device })
                .map({ $0.startedAt.addingTimeInterval(DeliveryTimeouts.lease) }).max() {
                earliest = max(earliest, horizon)
            }
            if nextWork == nil || earliest < nextWork!.earliest {
                nextWork = BackgroundWork(earliest: earliest, requiresNetwork: true)
            }
        }
        // OS budgets and disabled background refresh must not hide completed
        // retention changes. Persisted eligibility is retried on the next event.
        try? await background.replace(with: nextWork)
        return expired
    }
}
