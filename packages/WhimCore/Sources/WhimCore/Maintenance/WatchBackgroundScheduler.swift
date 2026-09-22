import Foundation
#if os(watchOS)
import WatchKit
#endif

@MainActor
public final class WatchBackgroundScheduler: BackgroundScheduling {
    private static let key = "whim.maintenance.request"
    private let defaults: UserDefaults
    private let schedule: @MainActor @Sendable (Date, String) async throws -> Void
    private var generation = 0

    public init(defaults: UserDefaults,
                schedule: @escaping @MainActor @Sendable (Date, String) async throws -> Void) {
        self.defaults = defaults; self.schedule = schedule
    }

    #if os(watchOS)
    public static let shared = WatchBackgroundScheduler(
        defaults: UserDefaults(suiteName: "group.app.whim.watch.shared")!
    ) { date, token in
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: date,
                userInfo: token as NSString) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
    #endif

    public func replace(with work: BackgroundWork?) async throws {
        generation += 1
        let submissionGeneration = generation
        guard let work else {
            // WatchKit has no cancellation API. Stale wakes complete without work.
            defaults.removeObject(forKey: Self.key)
            return
        }
        let token = UUID().uuidString
        try await schedule(work.earliest, token)
        guard generation == submissionGeneration else { return }
        defaults.set(token, forKey: Self.key)
    }

    public func accepts(_ userInfo: Any?) -> Bool {
        guard let token = userInfo as? String else { return false }
        return defaults.string(forKey: Self.key) == token
    }
}
