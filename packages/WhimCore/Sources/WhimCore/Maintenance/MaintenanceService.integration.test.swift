import Foundation
import XCTest
@testable import WhimCore

final class MaintenanceServiceTests: XCTestCase {
    func testSchedulingFailureStillReturnsExpiredNotesForPublication() async throws {
        let h = try MaintenanceHarness(policy: .immediately)
        defer { h.remove() }
        let note = try await h.note(sent: true)
        let expired = try await MaintenanceService(store: h.store, files: h.files,
            preferences: h.preferences, background: UnavailableBackgroundScheduler()).run(now: h.receivedAt)
        XCTAssertEqual(expired, [note.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.audioURL.path))
    }

    func testConfigurationChangeDoesNotSchedulePermanentlyFailedNoteWithoutUserRetry() async throws {
        let h = try MaintenanceHarness(policy: .never)
        defer { h.remove() }
        let note = try await h.note(sent: false)
        let old = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: h.receivedAt,
            endpoint: .init(scheme: "https", host: "example.com", path: "/old"))
        try await h.store.saveConfigurationRevision(old)
        let attempt = Attempt(noteID: note.id, configurationRevisionID: old.id, device: .iphone,
            endpoint: old.endpoint, startedAt: h.receivedAt)
        _ = try await h.store.apply(.attemptFailed(.init(attempt: attempt, failedAt: h.receivedAt,
            reason: .httpStatus(403))), to: note.id)
        let current = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: h.receivedAt.addingTimeInterval(1),
            endpoint: .init(scheme: "https", host: "example.com", path: "/new"))
        try await h.store.saveConfigurationRevision(current)
        let scheduler = MaintenanceBackgroundProbe()
        try await MaintenanceService(store: h.store, files: h.files, preferences: h.preferences,
            background: scheduler).run(now: h.receivedAt)
        let pending = await scheduler.request
        XCTAssertNil(pending)
    }

    func testEarliestRetryWinsUntilFailuresAreExhausted() async throws {
        let h = try MaintenanceHarness(policy: .oneDay)
        defer { h.remove() }
        _ = try await h.note(sent: true)
        let pending = try await h.note(sent: false)
        let revision = ConfigurationRevision(id: ConfigurationRevisionID(), changedAt: h.receivedAt,
            endpoint: .init(scheme: "https", host: "example.com", path: "/hook"))
        try await h.store.saveConfigurationRevision(revision)
        let scheduler = MaintenanceBackgroundProbe()
        let maintenance = MaintenanceService(store: h.store, files: h.files,
            preferences: h.preferences, background: scheduler)
        for count in 1...3 {
            let attempt = Attempt(noteID: pending.id, configurationRevisionID: revision.id, device: .iphone,
                endpoint: revision.endpoint, startedAt: h.receivedAt)
            _ = try await h.store.apply(.attemptFailed(.init(attempt: attempt,
                failedAt: h.receivedAt, reason: .network)), to: pending.id)
            try await maintenance.run(now: h.receivedAt)
            let scheduled = await scheduler.request
            let expectedDate: TimeInterval = count == 1 ? 10_000_060 : count == 2 ? 10_000_900 : 10_086_400
            XCTAssertEqual(scheduled, BackgroundWork(earliest: Date(timeIntervalSince1970: expectedDate), requiresNetwork: count < 3))
        }
    }


    func testSchedulesRetentionDeadlineAndCancelsAfterExpiry() async throws {
        let h = try MaintenanceHarness(policy: .oneDay)
        defer { h.remove() }
        _ = try await h.note(sent: true)
        let scheduler = MaintenanceBackgroundProbe()
        let maintenance = MaintenanceService(store: h.store, files: h.files,
            preferences: h.preferences, background: scheduler)
        try await maintenance.run(now: h.receivedAt)
        let scheduled = await scheduler.request
        XCTAssertEqual(scheduled, BackgroundWork(earliest: Date(timeIntervalSince1970: 10_086_400), requiresNetwork: false))
        try await maintenance.run(now: Date(timeIntervalSince1970: 10_086_400))
        let remaining = await scheduler.request
        XCTAssertNil(remaining)
    }

    func testPendingHandoffDefersDeletionButStillProtectsDeliveredAudio() async throws {
        let durability = MaintenanceDurability()
        let h = try MaintenanceHarness(policy: .immediately, durability: durability)
        defer { h.remove() }
        let note = try await h.note(sent: true)
        try await MaintenanceService(store: h.store, files: h.files, preferences: h.preferences)
            .run(now: h.receivedAt, preserving: [note.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.audioURL.path))
        XCTAssertTrue(durability.deliveredPaths.contains(note.audioURL.path))
    }

    // Break: delivered audio keeps the protection class that permits locked capture.
    func testDeliveredAudioGetsStrictProtectionEvenWhenKeptForever() async throws {
        let durability = MaintenanceDurability()
        let h = try MaintenanceHarness(policy: .never, durability: durability)
        defer { h.remove() }
        let note = try await h.note(sent: true)
        let unsent = try await h.note(sent: false)
        try await MaintenanceService(store: h.store, files: h.files, preferences: h.preferences)
            .run(now: h.receivedAt)
        XCTAssertTrue(durability.deliveredPaths.contains(note.audioURL.path))
        XCTAssertFalse(durability.deliveredPaths.contains(unsent.audioURL.path))
    }

    // Break: retention runs from recording time, ignores a policy, or removes history.
    func testAllRetentionChoicesExpireFromReceiptTime() async throws {
        let cases: [(RetentionPolicy, TimeInterval?)] = [
            (.immediately, 0), (.oneDay, 86_400), (.sevenDays, 604_800),
            (.thirtyDays, 2_592_000), (.ninetyDays, 7_776_000), (.never, nil)
        ]
        for (policy, interval) in cases {
            let h = try MaintenanceHarness(policy: policy)
            defer { h.remove() }
            let note = try await h.note(sent: true)
            let maintenance = MaintenanceService(store: h.store, files: h.files, preferences: h.preferences)
            if let interval, interval > 0 {
                try await maintenance.run(now: h.receivedAt.addingTimeInterval(interval - 1))
                XCTAssertTrue(FileManager.default.fileExists(atPath: note.audioURL.path), "\(policy)")
            }
            try await maintenance.run(now: h.receivedAt.addingTimeInterval(interval ?? 100_000_000))
            XCTAssertEqual(FileManager.default.fileExists(atPath: note.audioURL.path), interval == nil, "\(policy)")
            let history = try await h.store.listNotes(filter: .sent)
            XCTAssertEqual(history.count, 1)
            XCTAssertEqual(history.first?.title, "Keep this title")
            XCTAssertEqual(history.first?.hasLocalAudio, interval == nil, "\(policy)")
        }
    }

    // Break: automatic cleanup removes the only copy of an unsent or recovered Note.
    func testUnsentAndUnreviewedAudioNeverExpires() async throws {
        let h = try MaintenanceHarness(policy: .immediately)
        defer { h.remove() }
        let pending = try await h.note(sent: false)
        let recovered = try await h.note(sent: false, recovered: true)
        try await MaintenanceService(store: h.store, files: h.files, preferences: h.preferences)
            .run(now: h.receivedAt.addingTimeInterval(100_000_000))
        for note in [pending, recovered] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: note.audioURL.path))
            let reloaded = try await h.store.note(id: note.id)
            XCTAssertNil(reloaded?.audioExpiredAt)
        }
    }

    // Break: a crash between persisted expiry and unlink makes recovery report corruption.
    func testRecoveryCompletesPersistedExpiryWithoutLosingMetadata() async throws {
        let h = try MaintenanceHarness(policy: .immediately)
        defer { h.remove() }
        let note = try await h.note(sent: true)
        _ = try await h.store.markAudioExpired(noteID: note.id, at: h.receivedAt)
        let reopened = try SQLiteWhimStore.open(at: h.databaseURL)
        try await RecoveryScanner(store: reopened, files: h.files).scan()
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.audioURL.path))
        let reloaded = try await reopened.note(id: note.id)
        XCTAssertEqual(reloaded?.title, "Keep this title")
        XCTAssertNil(reloaded?.localError)
        XCTAssertNotNil(reloaded?.delivery.receipt)
    }
}

private struct MaintenanceHarness {
    let root: URL
    let store: SQLiteWhimStore
    let files: AudioFileStore
    let preferences: MaintenancePreferences
    let receivedAt = Date(timeIntervalSince1970: 10_000_000)
    var databaseURL: URL { root.appendingPathComponent("whim.sqlite") }

    init(policy: RetentionPolicy, durability: any FileDurability = SystemFileDurability()) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = try SQLiteWhimStore.open(at: root.appendingPathComponent("whim.sqlite"))
        files = try AudioFileStore(root: root.appendingPathComponent("Audio"), durability: durability, closeWriter: { _ in })
        preferences = MaintenancePreferences(policy: policy)
    }
    func note(sent: Bool, recovered: Bool = false) async throws -> Note {
        let session = RecordingSession(id: RecordingSessionID(), noteID: NoteID(),
            createdAt: Date(timeIntervalSince1970: 1_000), source: .iphone)
        try await store.saveRecordingSession(session)
        try writeAudioFixture(to: files.temporaryURL(for: session.id))
        let audio = try files.finalize(sessionID: session.id, noteID: session.noteID)
        let note = try await store.saveFinalized(.init(id: session.noteID, recordingSessionID: session.id,
            title: "Keep this title", titleSource: recovered ? .recovered : .timestamp,
            createdAt: session.createdAt, duration: 2, source: .iphone,
            captureOutcome: recovered ? .recovered : .completed, requiresReview: recovered, audioURL: audio.url))
        if sent {
            let attempt = Attempt(noteID: note.id, configurationRevisionID: ConfigurationRevisionID(),
                device: .iphone, endpoint: .init(scheme: "https", host: "example.com", path: "/hook"), startedAt: receivedAt)
            _ = try await store.apply(.attemptStarted(attempt), to: note.id)
            _ = try await store.apply(.receipt(.init(attemptID: attempt.id, noteID: note.id,
                receivedAt: receivedAt, statusCode: 204)), to: note.id)
        }
        return note
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class MaintenanceDurability: FileDurability, @unchecked Sendable {
    private let lock = NSLock()
    private var paths: Set<String> = []
    var deliveredPaths: Set<String> { lock.withLock { paths } }
    func protect(_ url: URL, as protection: AudioProtection) throws {
        try SystemFileDurability().protect(url, as: protection)
        if case .delivered = protection { _ = lock.withLock { paths.insert(url.path) } }
    }
    func synchronizeFile(at url: URL) throws { try SystemFileDurability().synchronizeFile(at: url) }
    func synchronizeDirectory(at url: URL) throws { try SystemFileDurability().synchronizeDirectory(at: url) }
}

private actor MaintenancePreferences: PreferenceStoring {
    private var value: PreferenceInput
    init(policy: RetentionPolicy) {
        value = .init(retentionPolicy: policy, transcriptionEnabled: false, transcriptionLocaleIdentifier: nil)
    }
    func load() -> PreferenceInput { value }
    func save(_ input: PreferenceInput) { value = input }
    func reset() { value = .default }
}

private actor MaintenanceBackgroundProbe: BackgroundScheduling {
    private(set) var request: BackgroundWork?
    func replace(with work: BackgroundWork?) { request = work }
}

private struct UnavailableBackgroundScheduler: BackgroundScheduling {
    struct Unavailable: Error {}
    func replace(with work: BackgroundWork?) async throws { throw Unavailable() }
}
