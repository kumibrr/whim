import Foundation
import XCTest
@testable import WhimCore

final class WatchBackgroundSchedulerTests: XCTestCase {
    @MainActor func testCancellationDuringSubmissionCannotRestorePendingWork() async throws {
        let suite = "whim-background-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let native = SuspendedWatchRefresh()
        let scheduler = WatchBackgroundScheduler(defaults: defaults) { _, token in
            await native.schedule(token)
        }
        let submission = Task { try await scheduler.replace(with: BackgroundWork(earliest: Date(), requiresNetwork: false)) }
        for _ in 0..<100 where native.token == nil { await Task.yield() }
        let token = try XCTUnwrap(native.token)
        try await scheduler.replace(with: nil)
        native.finish()
        try await submission.value
        XCTAssertFalse(scheduler.accepts(token))
    }

    @MainActor func testRejectedReplacementPreservesExistingWakeAndResetInvalidatesIt() async throws {
        let suite = "whim-background-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let native = WatchRefreshProbe()
        let scheduler = WatchBackgroundScheduler(defaults: defaults) { date, token in
            try native.schedule(date, token: token)
        }
        try await scheduler.replace(with: BackgroundWork(earliest: Date(timeIntervalSince1970: 100), requiresNetwork: true))
        let existing = try XCTUnwrap(native.tokens.first)
        XCTAssertTrue(scheduler.accepts(existing))
        native.reject = true
        do {
            try await scheduler.replace(with: BackgroundWork(earliest: Date(timeIntervalSince1970: 200), requiresNetwork: false))
            XCTFail("Expected native rejection")
        } catch is WatchRefreshProbe.Rejected {}
        XCTAssertTrue(scheduler.accepts(existing), "Rejected replacement must preserve the native outstanding request")
        try await scheduler.replace(with: nil)
        XCTAssertFalse(scheduler.accepts(existing))
    }
}

@MainActor private final class WatchRefreshProbe {
    struct Rejected: Error {}
    var reject = false
    var tokens: [String] = []
    func schedule(_ date: Date, token: String) throws {
        if reject { throw Rejected() }
        tokens.append(token)
    }
}

@MainActor private final class SuspendedWatchRefresh {
    var token: String?
    var continuation: CheckedContinuation<Void, Never>?
    func schedule(_ token: String) async {
        self.token = token
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(); continuation = nil }
}
