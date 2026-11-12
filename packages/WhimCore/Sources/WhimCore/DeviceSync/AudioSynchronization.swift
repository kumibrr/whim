import Foundation

/// Local availability of peer audio, independent of Delivery and its Receipt.
public struct AudioSynchronization: Codable, Equatable, Sendable {
    public static let maximumTransfers = 3
    public enum Status: String, Codable, Sendable { case waiting, retrying, failed }
    public internal(set) var status: Status
    public internal(set) var transferCount: Int
    public internal(set) var requestID: UUID?
    public internal(set) var lastFailure: AudioSynchronizationFailure?

    public init(status: Status = .waiting, transferCount: Int = 1, lastFailure: AudioSynchronizationFailure? = nil) {
        self.status = status; self.transferCount = transferCount; self.lastFailure = lastFailure
    }
}

/// One requested resend of Watch audio, retained after its synchronization cycle ends.
public struct AudioSynchronizationRetry: Codable, Equatable, Sendable, Identifiable {
    public enum Outcome: String, Codable, Sendable { case waiting, failed, synced, superseded }
    public let id: UUID
    public let startedAt: Date
    public internal(set) var outcome: Outcome
    public internal(set) var failure: AudioSynchronizationFailure?
    public internal(set) var completedAt: Date?

    init(id: UUID, startedAt: Date, outcome: Outcome = .waiting) {
        self.id = id; self.startedAt = startedAt; self.outcome = outcome
    }
}

/// Fixed local categories, never a free-form error message from a peer or filesystem.
public struct AudioSynchronizationFailure: Codable, Equatable, Sendable {
    public let reason: String
    public let observedAt: Date
    public let requestID: UUID?
    public let systemError: SynchronizationSystemError?
    public init(reason: String, observedAt: Date, requestID: UUID? = nil,
                systemError: SynchronizationSystemError? = nil) {
        self.reason = Self.reasons.contains(reason) ? reason : "unknown"
        self.observedAt = observedAt; self.requestID = requestID; self.systemError = systemError
    }
    private static let reasons: Set<String> = ["unreadableReceivedAudio", "sourceUnavailable", "missingNote",
        "missingAudio", "expiredAudio", "unreadableAudio", "sourceNotReady", "localSaveFailed", "unknown"]
    private enum CodingKeys: String, CodingKey { case reason, observedAt, requestID, systemError }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(reason: try values.decode(String.self, forKey: .reason),
            observedAt: try values.decode(Date.self, forKey: .observedAt),
            requestID: try values.decodeIfPresent(UUID.self, forKey: .requestID),
            systemError: try values.decodeIfPresent(SynchronizationSystemError.self, forKey: .systemError))
    }
}
