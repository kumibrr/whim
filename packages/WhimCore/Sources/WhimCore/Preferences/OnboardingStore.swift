import Foundation

public protocol OnboardingStoring: Sendable {
    func isComplete() async -> Bool
    func complete() async
    func reset() async
}

public final class UserDefaultsOnboardingStore: OnboardingStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    public init(suiteName: String = WhimProductionComposition.appGroupIdentifier) {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }
    public func isComplete() -> Bool { lock.withLock { defaults.bool(forKey: "onboarding.v1.completed") } }
    public func complete() { lock.withLock { defaults.set(true, forKey: "onboarding.v1.completed") } }
    public func reset() { lock.withLock { defaults.removeObject(forKey: "onboarding.v1.completed") } }
}
