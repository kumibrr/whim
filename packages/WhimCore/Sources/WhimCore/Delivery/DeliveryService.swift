import Foundation

public enum DeliveryResult: Equatable, Sendable {
    case setupRequired
    case queued
    case busy
    case alreadySent
    case sent
    case scheduled(Date)
    case failed
}

public struct ScheduledDelivery: Equatable, Sendable {
    public let noteID: NoteID
    public let earliest: Date
    public init(noteID: NoteID, earliest: Date) { self.noteID = noteID; self.earliest = earliest }
}

public protocol DeliveryScheduler: Sendable {
    func schedule(noteID: NoteID, earliest: Date,
                  operation: @escaping @Sendable () async -> Void) async
}

public struct DeliveryService: Sendable {
    private let store: any WhimStore
    private let credentialStore: any CredentialStore
    private let transport: any HTTPTransport
    private let notifications: any DeliveryNotificationAdapter
    private let scheduler: any DeliveryScheduler
    private let clock: any Clock
    private let isConnected: @Sendable () async -> Bool
    private let revisionForNote: @Sendable (NoteID) async throws -> ConfigurationRevision?
    private let requestBuilder: WebhookRequestBuilder
    private let appVersion: String
    private let appBuild: String
    private let device: AttemptDevice
    private let makeLeaseOwner: @Sendable () -> UUID
    private let titleSnapshot: @Sendable (Note) async -> TitleSnapshot

    public init(store: any WhimStore, credentials: any CredentialStore, transport: any HTTPTransport,
                notifications: any DeliveryNotificationAdapter, clock: any Clock = SystemClock(),
                scheduler: any DeliveryScheduler,
                isConnected: @escaping @Sendable () async -> Bool,
                configurationRevision: (@Sendable (NoteID) async throws -> ConfigurationRevision?)? = nil,
                requestBuilder: WebhookRequestBuilder = WebhookRequestBuilder(),
                titleSnapshot: @escaping @Sendable (Note) async -> TitleSnapshot = {
                    TitleSnapshot(noteID: $0.id, title: $0.title, source: $0.titleSource)
                },
                device: AttemptDevice = .iphone, appVersion: String, appBuild: String,
                makeLeaseOwner: @escaping @Sendable () -> UUID = { UUID() }) {
        self.store = store
        self.credentialStore = credentials
        self.transport = transport
        self.notifications = notifications
        self.scheduler = scheduler
        self.clock = clock
        self.isConnected = isConnected
        self.revisionForNote = configurationRevision ?? { try await store.configurationRevision(for: $0) }
        self.requestBuilder = requestBuilder
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.device = device
        self.makeLeaseOwner = makeLeaseOwner
        self.titleSnapshot = titleSnapshot
    }

    public func deliver(noteID: NoteID) async throws -> DeliveryResult {
        guard var note = try await store.note(id: noteID), note.isDeliveryEligible else {
            return (try await store.note(id: noteID))?.delivery.receipt == nil ? .failed : .alreadySent
        }
        if note.delivery.receipt != nil { return .alreadySent }

        for attempt in note.delivery.activeAttempts where
            clock.now.timeIntervalSince(attempt.startedAt) >= DeliveryTimeouts.lease {
            _ = try await store.apply(.attemptFailed(.init(attempt: attempt, failedAt: clock.now, reason: .network)), to: noteID)
        }
        guard let refreshed = try await store.note(id: noteID) else { return .failed }
        note = refreshed
        if note.delivery.receipt != nil { return .alreadySent }
        guard let revision = try await revisionForNote(noteID),
              try await credentialStore.credentials(for: revision.id) != nil else { return .setupRequired }
        guard await isConnected() else { return .queued }

        let currentFailures = note.delivery.failedAttempts.filter { $0.attempt.retryCycle == note.delivery.currentRetryCycle }
        if let permanent = currentFailures.first(where: { RetryPolicy.classification(for: $0.reason) == .permanent }) {
            await notifyOnce(note: note, reason: concise(permanent.reason))
            return .failed
        }
        if currentFailures.count >= RetryPolicy.maximumFailedAttempts {
            await notifyOnce(note: note, reason: "Webhook delivery exhausted its retries.")
            return .failed
        }
        if let last = currentFailures.last,
           let eligible = RetryPolicy.nextEligibility(after: currentFailures.count, now: last.failedAt,
                retryAfter: last.retryAfter), eligible > clock.now {
            return await scheduled(noteID: noteID, earliest: eligible)
        }

        let leaseOwner = makeLeaseOwner()
        guard try await store.acquireLease(.delivery, noteID: noteID, owner: leaseOwner,
            until: clock.now.addingTimeInterval(DeliveryTimeouts.lease)) else { return .busy }
        do {
            guard let freshNote = try await store.note(id: noteID) else {
                try await store.releaseLease(.delivery, noteID: noteID, owner: leaseOwner)
                return .failed
            }
            if freshNote.delivery.receipt != nil {
                try await store.releaseLease(.delivery, noteID: noteID, owner: leaseOwner)
                return .alreadySent
            }
            guard let freshRevision = try await revisionForNote(noteID),
                  let freshCredentials = try await credentialStore.credentials(for: freshRevision.id) else {
                try await store.releaseLease(.delivery, noteID: noteID, owner: leaseOwner)
                return .setupRequired
            }
            let result = try await perform(note: freshNote, revision: freshRevision, credentials: freshCredentials)
            try await store.releaseLease(.delivery, noteID: noteID, owner: leaseOwner)
            return result
        } catch {
            try? await store.releaseLease(.delivery, noteID: noteID, owner: leaseOwner)
            throw error
        }
    }

    public func retry(noteID: NoteID) async throws -> DeliveryResult {
        guard try await store.beginRetryCycle(noteID: noteID) else {
            return (try await store.note(id: noteID))?.delivery.receipt == nil ? .failed : .alreadySent
        }
        return try await deliver(noteID: noteID)
    }

    public func retryAllFailed() async throws -> [NoteID: DeliveryResult] {
        var results: [NoteID: DeliveryResult] = [:]
        for projection in try await store.listNotes(filter: .failed) {
            results[projection.id] = try await retry(noteID: projection.id)
        }
        return results
    }

    private func perform(note: Note, revision: ConfigurationRevision,
                         credentials: StoredWebhookCredentials) async throws -> DeliveryResult {
        let snapshot = note.titleSource == .transcription
            ? TitleSnapshot(noteID: note.id, title: note.title, source: note.titleSource)
            : await titleSnapshot(note)
        let deliveryNote = Note(id: note.id, recordingSessionID: note.recordingSessionID,
            title: snapshot.title, titleSource: snapshot.source, createdAt: note.createdAt,
            duration: note.duration, source: note.source, captureOutcome: note.captureOutcome,
            requiresReview: note.requiresReview, audioURL: note.audioURL, workflowID: note.workflowID,
            delivery: note.delivery, localError: note.localError)
        let attempt = Attempt(noteID: note.id, configurationRevisionID: revision.id, device: device,
            endpoint: revision.endpoint, startedAt: clock.now, retryCycle: note.delivery.currentRetryCycle)
        let request: WebhookRequest
        do {
            request = try requestBuilder.build(note: deliveryNote, attemptID: attempt.id, credentials: credentials,
                timestamp: Int64(clock.now.timeIntervalSince1970), appVersion: appVersion, appBuild: appBuild)
        } catch {
            try await store.recordLocalError(FileManager.default.fileExists(atPath: note.audioURL.path) ? .unreadable : .missing,
                noteID: note.id)
            return .failed
        }
        defer { request.removeBodyFile() }
        let started = try await store.apply(.attemptStarted(attempt), to: note.id)
        if started.receipt != nil { return .sent }
        do {
            let response = try await transport.send(request)
            if (200...299).contains(response.statusCode) {
                let receipt = Receipt(attemptID: attempt.id, noteID: note.id, receivedAt: clock.now,
                    statusCode: response.statusCode)
                _ = try await store.apply(.receipt(receipt), to: note.id)
                return .sent
            }
            return try await recordFailure(attempt: attempt, note: note, reason: .httpStatus(response.statusCode),
                retryAfter: retryAfter(response.header("Retry-After")), excerpt: sanitizedExcerpt(response.body,
                    note: note, credentials: credentials))
        } catch {
            return try await recordFailure(attempt: attempt, note: note, reason: .network,
                retryAfter: nil, excerpt: nil)
        }
    }

    private func recordFailure(attempt: Attempt, note: Note, reason: AttemptFailureReason,
                               retryAfter: Date?, excerpt: String?) async throws -> DeliveryResult {
        let delivery = try await store.apply(.attemptFailed(.init(attempt: attempt, failedAt: clock.now,
            reason: reason, retryAfter: retryAfter, responseExcerpt: excerpt)), to: note.id)
        if delivery.receipt != nil { return .sent }
        let current = delivery.failedAttempts.filter { $0.attempt.retryCycle == delivery.currentRetryCycle }
        if RetryPolicy.classification(for: reason) == .permanent || current.count >= RetryPolicy.maximumFailedAttempts {
            let updated = (try await store.note(id: note.id)) ?? note
            await notifyOnce(note: updated, reason: concise(reason))
            return .failed
        }
        let next = RetryPolicy.nextEligibility(after: current.count, now: clock.now, retryAfter: retryAfter)!
        return await scheduled(noteID: note.id, earliest: next)
    }

    private func notifyOnce(note: Note, reason: String) async {
        if (try? await store.markExhaustionNotified(noteID: note.id,
            retryCycle: note.delivery.currentRetryCycle)) == true {
            await notifications.notifyFailure(title: note.title, reason: reason, noteID: note.id)
        }
    }

    private func retryAfter(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value) { return clock.now.addingTimeInterval(max(0, seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }

    private func sanitizedExcerpt(_ body: Data, note: Note, credentials: StoredWebhookCredentials) -> String? {
        guard !body.isEmpty else { return nil }
        var value = String(decoding: body, as: UTF8.self)
        var secrets = [note.title, credentials.bearerToken, credentials.hmacSecret].compactMap { $0 }
        secrets += credentials.customHeaders.map(\.value)
        if let components = URLComponents(url: credentials.endpoint, resolvingAgainstBaseURL: false) {
            secrets += components.queryItems?.compactMap(\.value) ?? []
        }
        for secret in secrets where !secret.isEmpty { value = value.replacingOccurrences(of: secret, with: "<redacted>") }
        let capped = Data(value.utf8.prefix(DeliveryTimeouts.maximumErrorExcerptBytes))
        return String(decoding: capped, as: UTF8.self)
    }

    private func concise(_ reason: AttemptFailureReason) -> String {
        switch reason {
        case .network: "The webhook could not be reached."
        case .httpStatus(let code): "The webhook returned HTTP \(code)."
        }
    }

    private func scheduled(noteID: NoteID, earliest: Date) async -> DeliveryResult {
        await scheduler.schedule(noteID: noteID, earliest: earliest) {
            _ = try? await deliver(noteID: noteID)
        }
        return .scheduled(earliest)
    }
}
