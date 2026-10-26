import Foundation

/// Local availability of peer audio, independent of Delivery and its Receipt.
public struct AudioSynchronization: Codable, Equatable, Sendable {
    public static let maximumTransfers = 3
    public enum Status: String, Codable, Sendable { case waiting, retrying, failed }
    public internal(set) var status: Status
    public internal(set) var transferCount: Int
    var requestID: UUID?

    public init(status: Status = .waiting, transferCount: Int = 1) {
        self.status = status; self.transferCount = transferCount
    }
}

/// One requested resend of Watch audio, retained after its synchronization cycle ends.
public struct AudioSynchronizationRetry: Codable, Equatable, Sendable, Identifiable {
    public enum Outcome: String, Codable, Sendable { case waiting, failed, synced, superseded }
    public let id: UUID
    public let startedAt: Date
    public internal(set) var outcome: Outcome

    init(id: UUID, startedAt: Date, outcome: Outcome = .waiting) {
        self.id = id; self.startedAt = startedAt; self.outcome = outcome
    }
}
