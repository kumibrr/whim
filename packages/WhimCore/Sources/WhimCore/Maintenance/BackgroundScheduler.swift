import Foundation

public struct BackgroundWork: Equatable, Sendable {
    public let earliest: Date
    public let requiresNetwork: Bool
    public init(earliest: Date, requiresNetwork: Bool) {
        self.earliest = earliest; self.requiresNetwork = requiresNetwork
    }
}

/// Replaces the one outstanding OS request; nil cancels it.
public protocol BackgroundScheduling: Sendable {
    func replace(with work: BackgroundWork?) async throws
}

public struct NoBackgroundScheduler: BackgroundScheduling {
    public init() {}
    public func replace(with work: BackgroundWork?) async throws {}
}
