import Foundation

public actor ConnectivityMergeService {
    private let store: any WhimStore
    private let files: any AudioFileManaging
    private let root: URL
    private let journal: ConnectivityJournal
    private let device: AttemptDevice
    private let credentials: (any CredentialStore)?
    private let transport: (any PeerTransport)?
    private var lastConfigurationContext: String?

    public init(store: any WhimStore, files: any AudioFileManaging, databaseURL: URL,
                root: URL, device: AttemptDevice, credentials: (any CredentialStore)? = nil, transport: (any PeerTransport)? = nil) throws {
        self.store = store; self.files = files; self.root = root; self.device = device; self.credentials = credentials; self.transport = transport
        journal = try ConnectivityJournal(databaseURL: databaseURL)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult public func apply(_ envelope: ConnectivityEnvelope) async throws -> NoteID? {
        guard envelope.schemaVersion == 1 else { throw ConnectivityError.unsupportedSchema }
        let needsAppliedAcknowledgement: Bool
        switch envelope.payload { case .reset, .deletion: needsAppliedAcknowledgement = true; default: needsAppliedAcknowledgement = false }
        if !needsAppliedAcknowledgement, try journal.wasApplied(envelope.messageID) {
            try acknowledgeDurable(envelope)
            return nil
        }
        let result = try await applyNew(envelope)
        if envelope.generation == (try generation()) { try journal.markApplied(envelope.messageID) }
        return result
    }

    private func applyNew(_ envelope: ConnectivityEnvelope) async throws -> NoteID? {
        guard envelope.schemaVersion == 1 else { throw ConnectivityError.unsupportedSchema }
        if case .reset = envelope.payload {
            try await applyReset(envelope)
            try acknowledgeDurable(envelope)
            return nil
        }
        let state = try journal.resetState()
        if !state.complete { try await eraseForReset(state.generation) }
        guard envelope.generation >= state.generation else { return nil }
        try journal.append(envelope)
        if case .deletion = envelope.payload {} else { try acknowledgeDurable(envelope) }
        guard envelope.generation == state.generation else { return nil }
        switch envelope.payload {
        case .acknowledgement(.durable(let id)):
            try journal.acknowledge(id, durableOnly: true)
            return nil
        case .deletion(let id):
            try await store.delete(noteID: id)
            try journal.discardNotePayloads(id)
            try files.delete(noteID: id)
            try removePendingFile(id)
            try await store.acknowledgeDeletion(noteID: id, endpoint: device)
            try acknowledgeDurable(envelope)
            try journal.enqueue(.init(generation: envelope.generation, payload: .acknowledgement(.deletion(id, device))), resubmit: true)
            return id
        case .acknowledgement(.deletion(let id, let endpoint)):
            if (try await store.deletions()).contains(where: { $0.noteID == id }) {
                try await store.acknowledgeDeletion(noteID: id, endpoint: endpoint)
                if endpoint != device { try journal.acknowledgeApplied(.deletion(id), generation: envelope.generation) }
            }
            return nil
        case .acknowledgement(.configuration(let id)):
            if try await store.latestConfigurationRevision()?.id == id {
                try journal.write([envelope.sentAt], key: "lastSynchronizedAt")
            }
            return nil
        case .acknowledgement(.reset(let endpoint)):
            lastConfigurationContext = nil
            var endpoints = try journal.read("resetAcknowledged", as: [String].self) ?? []
            if !endpoints.contains(endpoint.rawValue) { endpoints.append(endpoint.rawValue) }
            try journal.write(endpoints, key: "resetAcknowledged")
            if endpoint != device { try journal.acknowledgeApplied(.reset, generation: envelope.generation) }
            try journal.write([envelope.sentAt], key: "lastSynchronizedAt")
            return nil
        default: break
        }
        guard let id = envelope.payload.noteID else { return nil }
        for message in try journal.inbox() where message.generation == envelope.generation {
            if case .noteMetadata(let metadata) = message.payload, metadata.id == id {
                _ = try await importNote(metadata)
            }
        }
        return try await mergeState(id)

    }

    /// The platform adapter already owns the received file before invoking this actor.
    @discardableResult public func receiveFile(at url: URL, metadata envelope: ConnectivityEnvelope) async throws -> NoteID? {
        guard envelope.schemaVersion == 1 else { throw ConnectivityError.unsupportedSchema }
        guard envelope.generation >= (try journal.resetState().generation) else { return nil }
        guard case .noteMetadata(let metadata) = envelope.payload,
              files.audioError(at: url) == nil else { throw ConnectivityError.invalidFile }
        guard !(try await store.deletions()).contains(where: { $0.noteID == metadata.id }) else { return nil }
        let destination = pendingFile(metadata.id, generation: envelope.generation)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: url, to: destination)
        }
        let durability = SystemFileDurability()
        let sidecar = destination.appendingPathExtension("plist")
        try envelope.encoded().write(to: sidecar, options: .atomic)
        try durability.protect(sidecar, as: .unsent)
        try durability.synchronizeFile(at: sidecar)
        try durability.protect(destination, as: .unsent)
        try durability.synchronizeFile(at: destination)
        try durability.synchronizeDirectory(at: destination.deletingLastPathComponent())
        try durability.synchronizeDirectory(at: root)
        try acknowledgeDurable(envelope)
        guard envelope.generation == (try generation()) else { return nil }
        for message in try journal.inbox() where message.generation == envelope.generation {
            if case .noteMetadata(let value) = message.payload, value.id == metadata.id {
                _ = try await importNote(value)
                return try await mergeState(value.id)
            }
        }
        return nil
    }

    private func importNote(_ metadata: NoteTransfer) async throws -> NoteID? {
        guard !(try await store.deletions()).contains(where: { $0.noteID == metadata.id }) else {
            try removePendingFile(metadata.id); return nil
        }
        if try await store.note(id: metadata.id) != nil { try removePendingFile(metadata.id); return metadata.id }
        let pending = pendingFile(metadata.id)
        guard FileManager.default.fileExists(atPath: pending.path) else { return nil }
        let destination = files.audioURL(for: metadata.id)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: pending, to: destination)
        }
        guard try files.durableAudio(noteID: metadata.id) != nil else { throw ConnectivityError.invalidFile }
        _ = try await store.saveFinalized(metadata.finalized(audioURL: destination))
        try removePendingFile(metadata.id)
        return metadata.id
    }

    private func mergeState(_ id: NoteID) async throws -> NoteID? {
        guard try await store.note(id: id) != nil else { return nil }
        let current = try generation()
        let messages = try journal.inbox().filter { $0.payload.noteID == id && $0.generation == current }
        for message in messages {
            switch message.payload {
            case .attempt(let attempt): _ = try await store.apply(attempt.event, to: id)
            case .receipt(let receipt): _ = try await store.apply(.receipt(receipt), to: id)
            default: break
            }
        }
        // iPhone is the sole enrichment writer. A deterministic lexical tie-break also
        // converges duplicate transcription completions without trusting device clocks.
        let titles = messages.compactMap { message -> TitleTransfer? in
            if case .title(let title) = message.payload, title.source == .transcription { return title }
            return nil
        }.sorted { $0.title < $1.title }
        if let title = titles.last { try await store.updateTitle(noteID: id, title: title.title, source: title.source) }
        return id
    }

    /// Credentials arrive only through the authenticated system peer context, and go
    /// directly to Keychain. They never enter the protocol journal.
    public func receiveConfiguration(_ envelope: ConnectivityEnvelope, credentials secrets: StoredWebhookCredentials) async throws {
        guard envelope.schemaVersion == 1 else { throw ConnectivityError.unsupportedSchema }
        guard case .configuration(let revision) = envelope.payload, device == .appleWatch,
              envelope.generation == (try generation()), try journal.resetState().complete,
              let credentials else { return }
        let validation = WebhookValidator.validate(.init(endpoint: secrets.endpoint.absoluteString,
            bearerToken: secrets.bearerToken, hmacSecret: secrets.hmacSecret, customHeaders: secrets.customHeaders))
        guard validation.value != nil else { throw ConnectivityError.invalidConfiguration }
        if let latest = try await store.latestConfigurationRevision(),
           (latest.changedAt, latest.id.rawValue.uuidString) > (revision.changedAt, revision.id.rawValue.uuidString) { return }
        try await credentials.save(secrets, for: revision.id)
        try await store.saveConfigurationRevision(revision)
        try journal.write([envelope.sentAt], key: "lastSynchronizedAt")
        try journal.enqueue(.init(generation: envelope.generation, payload: .acknowledgement(.configuration(revision.id))))
    }

    /// Finish destructive work before admitting any new Recording Session.
    @discardableResult public func recoverReset() async throws -> Bool {
        let before = try journal.resetState()
        let resets = try journal.inbox().filter { if case .reset = $0.payload { true } else { false } }
        if let latest = resets.max(by: { $0.generation < $1.generation }) { _ = try await apply(latest) }
        let state = try journal.resetState()
        if !state.complete { try await eraseForReset(state.generation) }
        return !before.complete || before.generation != state.generation
    }

    public func recover() async throws {
        try await recoverReset()
        try await recoverPreparedState()
    }

    public func recoverPreparedState() async throws {
        let state = try journal.resetState()
        for envelope in try journal.inbox() where envelope.generation == state.generation {
            if case .reset = envelope.payload { continue }
            _ = try await applyNew(envelope)
        }
        for deletion in try await store.deletions() {
            try files.delete(noteID: deletion.noteID)
            if Set(deletion.acknowledgedEndpoints).count < 2 { try await queueDeletion(deletion.noteID) }
        }
    }

    public func queueNote(_ id: NoteID) async throws {
        guard try journal.resetState().complete else { return }
        guard let note = try await store.note(id: id) else { return }
        let current = try generation()
        let metadata = ConnectivityEnvelope(generation: current, payload: .noteMetadata(.init(note)))
        try journal.enqueue(metadata)
        if device == .appleWatch, note.source == .appleWatch, files.audioError(at: note.audioURL) == nil {
            try journal.enqueue(.init(generation: current, payload: metadata.payload), file: note.audioURL)
        }
        for attempt in try await store.deliveryAttempts(noteID: id) {
            if let failure = note.delivery.failedAttempts.first(where: { $0.attempt.id == attempt.id }) {
                // Error excerpts remain local, even if the HTTP adapter sanitized them.
                let transfer = AttemptFailure(attempt: failure.attempt, failedAt: failure.failedAt,
                    reason: failure.reason, retryAfter: failure.retryAfter)
                try journal.enqueue(.init(generation: current, payload: .attempt(.failed(transfer))))
            } else { try journal.enqueue(.init(generation: current, payload: .attempt(.started(attempt)))) }
        }
        if let receipt = note.delivery.receipt { try journal.enqueue(.init(generation: current, payload: .receipt(receipt))) }
        if device == .iphone, note.titleSource == .transcription {
            try journal.enqueue(.init(generation: current, payload: .title(.init(noteID: id, title: note.title, source: .transcription))))
        }
        try await flush()
    }

    public func queueDeletion(_ id: NoteID) async throws {
        try journal.enqueue(.init(generation: generation(), payload: .deletion(id)))
        try journal.discardNotePayloads(id)
        try removePendingFile(id)
        try await store.acknowledgeDeletion(noteID: id, endpoint: device)
        try await flush()
    }

    public func flush() async throws {
        // Activation alone does not mean a companion is installed. Keep the
        // journal pending until it is available; reachability is not required.
        guard let transport, transport.isActivated, transport.isAvailable else { return }
        let current = try generation()
        for pending in try journal.outgoing() {
            guard pending.envelope.generation == current else {
                try journal.submitted(pending.envelope.messageID); continue
            }
            if let file = pending.file {
                if FileManager.default.fileExists(atPath: file.path) { try transport.transferFile(at: file, metadata: pending.envelope) }
            } else { try transport.transfer(pending.envelope) }
            if case .acknowledgement = pending.envelope.payload { try journal.acknowledge(pending.envelope.messageID) }
            else { try journal.submitted(pending.envelope.messageID) }
        }
        if device == .iphone, let revision = try await store.latestConfigurationRevision(),
           let secret = try await credentials?.credentials(for: revision.id) {
            let identity = String(current.counter) + current.origin.uuidString + revision.id.rawValue.uuidString
            if lastConfigurationContext != identity {
                try transport.updateContext(.init(generation: current, payload: .configuration(revision)), credentials: secret)
                lastConfigurationContext = identity
            }
        }
    }

    public func activated() async throws {
        try journal.replayUnacknowledged()
        lastConfigurationContext = nil
        try await flush()
    }

    private func acknowledgeDurable(_ envelope: ConnectivityEnvelope) throws {
        if case .acknowledgement = envelope.payload { return }
        if case .configuration = envelope.payload { return }
        try journal.enqueue(.init(generation: envelope.generation, payload: .acknowledgement(.durable(envelope.messageID))), resubmit: true)
    }

    public func completeReceivedFile(_ url: URL) throws { try transport?.completeReceivedFile(url) }

    public func retryTransfer(_ id: UUID) async throws {
        try journal.submitted(id, value: false)
        try await flush()
    }

    public func status() throws -> WatchSettingsProjection {
        let reset = try journal.resetState()
        let endpoints = try journal.read("resetAcknowledged", as: [String].self) ?? []
        return WatchSettingsProjection(availability: transport?.isAvailable == true ? "available" : "unavailable",
            lastSynchronizedAt: try journal.read("lastSynchronizedAt", as: [Date].self)?.first,
            resetState: reset.generation == .initial ? "idle" : endpoints.count >= 2 ? "synchronized" : "pending")
    }

    public func generation() throws -> ResetGeneration { try journal.resetState().generation }

    public func prepareReset(now: Date = Date()) throws -> ConnectivityEnvelope {
        let current = try generation()
        let ticks = UInt64(max(0, now.timeIntervalSince1970 * 1_000))
        let next = ResetGeneration(counter: max(current.counter, ticks) + 1, origin: UUID())
        let envelope = ConnectivityEnvelope(generation: next, payload: .reset)
        try journal.enqueue(envelope, reset: .init(generation: next, complete: false))
        return envelope
    }

    private func applyReset(_ envelope: ConnectivityEnvelope) async throws {
        let state = try journal.resetState()
        guard envelope.generation >= state.generation else { return }
        if envelope.generation == state.generation && state.complete {
            try journal.enqueue(.init(generation: state.generation, payload: .acknowledgement(.reset(device))), resubmit: true)
            return
        }
        try journal.write(ConnectivityJournal.ResetState(generation: envelope.generation, complete: false), key: "reset")
        try await eraseForReset(envelope.generation)
        for pending in try journal.inbox() where pending.generation == envelope.generation {
            _ = try await applyNew(pending)
        }
    }

    private func eraseForReset(_ generation: ResetGeneration) async throws {
        // Barrier is already durable. Repeating erasure after a crash is safe until complete.
        for id in try files.durableNoteIDs() { try files.delete(noteID: id) }
        for session in try await store.recordingSessions() { try files.deleteTemporary(sessionID: session.id) }
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            let parts = file.lastPathComponent.split(separator: "_", maxSplits: 1)
            if parts.count == 2, let counter = UInt64(parts[0]), let origin = UUID(uuidString: String(parts[1])),
               ResetGeneration(counter: counter, origin: origin) < generation { try FileManager.default.removeItem(at: file) }
        }
        try await store.reset()
        try await credentials?.removeAll()
        try journal.discard(before: generation)
        try journal.write([Date](), key: "lastSynchronizedAt")
        try journal.write([device.rawValue], key: "resetAcknowledged")
        try journal.write(ConnectivityJournal.ResetState(generation: generation, complete: true), key: "reset")
        try journal.enqueue(.init(generation: generation, payload: .acknowledgement(.reset(device))), resubmit: true)
    }

    private func removePendingFile(_ id: NoteID) throws {
        let audio = pendingFile(id)
        for file in [audio, audio.appendingPathExtension("plist")] where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        if FileManager.default.fileExists(atPath: audio.deletingLastPathComponent().path) {
            try SystemFileDurability().synchronizeDirectory(at: audio.deletingLastPathComponent())
        }
    }

    private func pendingFile(_ id: NoteID, generation: ResetGeneration? = nil) -> URL {
        let current = generation ?? (try? self.generation()) ?? .initial
        return root.appendingPathComponent(String(current.counter) + "_" + current.origin.uuidString)
            .appendingPathComponent(id.rawValue.uuidString + ".m4a")
    }
}
