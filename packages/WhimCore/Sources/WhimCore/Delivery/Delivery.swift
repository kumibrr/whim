import Foundation

public struct AttemptID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: UUID())
    }
}

public enum AttemptDevice: String, Codable, Sendable {
    case iphone
    case appleWatch = "apple_watch"
}

public enum AttemptFailureReason: Codable, Equatable, Sendable {
    case network
    case httpStatus(Int)
}

public struct SanitizedEndpoint: Codable, Equatable, Sendable {
    public let scheme: String
    public let host: String
    public let port: Int?
    public let path: String

    public init(scheme: String, host: String, port: Int? = nil, path: String) {
        self.scheme = scheme.lowercased()
        self.host = host.lowercased()
        self.port = port
        self.path = path.isEmpty ? "/" : path
    }

    public init?(url: URL) {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        self.init(scheme: scheme, host: host, port: url.port, path: url.path)
    }
}

public struct Attempt: Codable, Equatable, Sendable {
    public let id: AttemptID
    public let noteID: NoteID
    public let configurationRevisionID: ConfigurationRevisionID
    public let device: AttemptDevice
    public let endpoint: SanitizedEndpoint
    public let startedAt: Date
    public let retryCycle: Int

    public init(
        id: AttemptID = AttemptID(),
        noteID: NoteID,
        configurationRevisionID: ConfigurationRevisionID,
        device: AttemptDevice,
        endpoint: SanitizedEndpoint,
        startedAt: Date,
        retryCycle: Int = 0
    ) {
        self.id = id
        self.noteID = noteID
        self.configurationRevisionID = configurationRevisionID
        self.device = device
        self.endpoint = endpoint
        self.startedAt = startedAt
        self.retryCycle = retryCycle
    }

    private enum CodingKeys: String, CodingKey {
        case id, noteID, configurationRevisionID, device, endpoint, startedAt, retryCycle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(AttemptID.self, forKey: .id)
        noteID = try container.decode(NoteID.self, forKey: .noteID)
        configurationRevisionID = try container.decode(ConfigurationRevisionID.self, forKey: .configurationRevisionID)
        device = try container.decode(AttemptDevice.self, forKey: .device)
        endpoint = try container.decode(SanitizedEndpoint.self, forKey: .endpoint)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        retryCycle = try container.decodeIfPresent(Int.self, forKey: .retryCycle) ?? 0
    }
}

public struct AttemptFailure: Codable, Equatable, Sendable {
    public let attempt: Attempt
    public let failedAt: Date
    public let reason: AttemptFailureReason
    public let retryAfter: Date?
    /// A bounded, non-secret excerpt prepared by the HTTP transport before persistence.
    public let responseExcerpt: String?

    public init(
        attempt: Attempt,
        failedAt: Date,
        reason: AttemptFailureReason,
        retryAfter: Date? = nil,
        responseExcerpt: String? = nil
    ) {
        self.attempt = attempt
        self.failedAt = failedAt
        self.reason = reason
        self.retryAfter = retryAfter
        self.responseExcerpt = responseExcerpt
    }
}

public struct Receipt: Codable, Equatable, Sendable {
    public let attemptID: AttemptID
    public let noteID: NoteID
    public let receivedAt: Date
    public let statusCode: Int

    public init(attemptID: AttemptID, noteID: NoteID, receivedAt: Date, statusCode: Int) {
        self.attemptID = attemptID
        self.noteID = noteID
        self.receivedAt = receivedAt
        self.statusCode = statusCode
    }
}

public enum DeliveryStatus: String, Codable, Sendable {
    case setupRequired = "setup_required"
    case queued
    case sending
    case sent
    case failed
}

public struct Delivery: Codable, Equatable, Sendable {
    public internal(set) var hasUsableConfiguration: Bool
    public internal(set) var isConnected: Bool
    public internal(set) var hasExecutionLease: Bool
    public internal(set) var activeAttempts: [Attempt]
    public internal(set) var failedAttempts: [AttemptFailure]
    public internal(set) var receipt: Receipt?
    public internal(set) var currentRetryCycle: Int

    public init(
        hasUsableConfiguration: Bool = false,
        isConnected: Bool = true,
        hasExecutionLease: Bool = false,
        activeAttempts: [Attempt] = [],
        failedAttempts: [AttemptFailure] = [],
        receipt: Receipt? = nil,
        currentRetryCycle: Int = 0
    ) {
        self.hasUsableConfiguration = hasUsableConfiguration
        self.isConnected = isConnected
        self.hasExecutionLease = hasExecutionLease
        self.activeAttempts = activeAttempts
        self.failedAttempts = failedAttempts
        self.receipt = receipt
        self.currentRetryCycle = currentRetryCycle
    }

    public static let pending = Delivery()

    public var status: DeliveryStatus {
        if receipt != nil { return .sent }
        if activeAttempts.contains(where: { $0.retryCycle == currentRetryCycle }) { return .sending }
        if !hasUsableConfiguration { return .setupRequired }

        let currentFailures = failedAttempts.filter { $0.attempt.retryCycle == currentRetryCycle }
        let hasPermanentFailure = currentFailures.contains {
            RetryPolicy.classification(for: $0.reason) == .permanent
        }
        let retryableFailureCount = currentFailures.count {
            RetryPolicy.classification(for: $0.reason) == .retryable
        }
        if hasPermanentFailure || retryableFailureCount >= RetryPolicy.maximumFailedAttempts {
            return .failed
        }
        return .queued
    }
}

public enum DeliveryEvent: Codable, Equatable, Sendable {
    case configurationAvailabilityChanged(Bool)
    case connectivityChanged(Bool)
    case leaseChanged(Bool)
    case attemptStarted(Attempt)
    case attemptFailed(AttemptFailure)
    case receipt(Receipt)
}
