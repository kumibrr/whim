import Foundation

/// Safe system identity only. Never retain NSError descriptions or userInfo.
public struct SynchronizationSystemError: Codable, Equatable, Sendable {
    public let domain: String?
    public let code: Int?
    public let observedAt: Date?
    public var category: String {
        guard let domain, let code else { return "unknown" }
        if (domain == NSPOSIXErrorDomain && code == Int(POSIXErrorCode.ENOSPC.rawValue)) ||
            (domain == NSCocoaErrorDomain && code == NSFileWriteOutOfSpaceError) { return "storageFull" }
        guard domain == "WCErrorDomain" else { return "unknown" }
        switch code {
        case 7002: return "sessionNotSupported"
        case 7003: return "sessionMissingDelegate"
        case 7004: return "sessionNotActivated"
        case 7005: return "deviceNotPaired"
        case 7006: return "watchAppNotInstalled"
        case 7007: return "notReachable"
        case 7008: return "invalidParameter"
        case 7009: return "payloadTooLarge"
        case 7010: return "unsupportedPayload"
        case 7011: return "messageReplyFailed"
        case 7012: return "replyTimedOut"
        case 7013: return "fileAccessDenied"
        case 7014: return "deliveryFailed"
        case 7015: return "storageFull"
        case 7016: return "sessionInactive"
        case 7017: return "transferTimedOut"
        case 7018: return "companionAppNotInstalled"
        case 7019: return "watchOnlyApp"
        default: return "unknown"
        }
    }

    public init(error: any Error, observedAt: Date) {
        let error = error as NSError
        self.init(domain: error.domain, code: error.code, observedAt: observedAt)
    }

    private static let safeDomains: Set<String> = ["WCErrorDomain", NSCocoaErrorDomain,
        NSPOSIXErrorDomain, "AVFoundationErrorDomain", "NSOSStatusErrorDomain", NSURLErrorDomain]
    private init(domain: String?, code: Int?, observedAt: Date?) {
        let allowed = domain.map { Self.safeDomains.contains($0) } == true
        self.domain = allowed ? domain : nil; self.code = allowed ? code : nil
        self.observedAt = observedAt
    }
    private enum CodingKeys: String, CodingKey { case domain, code, observedAt }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(domain: try values.decodeIfPresent(String.self, forKey: .domain),
            code: try values.decodeIfPresent(Int.self, forKey: .code),
            observedAt: try values.decodeIfPresent(Date.self, forKey: .observedAt))
    }
}

/// A local, current-session view of OS connection facts. Nil facts are unknown.
public struct PeerConnectionDetails: Codable, Equatable, Sendable {
    public let supported: Bool?
    public let activationState: String?
    public let paired: Bool?
    public let counterpartAppInstalled: Bool?
    public let reachable: Bool?
    public let pendingStateTransfers: Int?
    public let pendingAudioTransfers: Int?
    public let activationFailure: SynchronizationSystemError?
    public let lastTransferFailure: SynchronizationSystemError?

    public init(supported: Bool? = nil, activationState: String? = nil, paired: Bool? = nil,
                counterpartAppInstalled: Bool? = nil, reachable: Bool? = nil,
                pendingStateTransfers: Int? = nil, pendingAudioTransfers: Int? = nil,
                activationFailure: SynchronizationSystemError? = nil,
                lastTransferFailure: SynchronizationSystemError? = nil) {
        self.supported = supported
        self.activationState = activationState.flatMap { ["notActivated", "inactive", "activated"].contains($0) ? $0 : nil }
        self.paired = paired
        self.counterpartAppInstalled = counterpartAppInstalled; self.reachable = reachable
        self.pendingStateTransfers = pendingStateTransfers.flatMap { $0 >= 0 ? $0 : nil }
        self.pendingAudioTransfers = pendingAudioTransfers.flatMap { $0 >= 0 ? $0 : nil }
        self.activationFailure = activationFailure; self.lastTransferFailure = lastTransferFailure
    }

    private enum CodingKeys: String, CodingKey {
        case supported, activationState, paired, counterpartAppInstalled, reachable
        case pendingStateTransfers, pendingAudioTransfers, activationFailure, lastTransferFailure
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(supported: try values.decodeIfPresent(Bool.self, forKey: .supported),
            activationState: try values.decodeIfPresent(String.self, forKey: .activationState),
            paired: try values.decodeIfPresent(Bool.self, forKey: .paired),
            counterpartAppInstalled: try values.decodeIfPresent(Bool.self, forKey: .counterpartAppInstalled),
            reachable: try values.decodeIfPresent(Bool.self, forKey: .reachable),
            pendingStateTransfers: try values.decodeIfPresent(Int.self, forKey: .pendingStateTransfers),
            pendingAudioTransfers: try values.decodeIfPresent(Int.self, forKey: .pendingAudioTransfers),
            activationFailure: try values.decodeIfPresent(SynchronizationSystemError.self, forKey: .activationFailure),
            lastTransferFailure: try values.decodeIfPresent(SynchronizationSystemError.self, forKey: .lastTransferFailure))
    }
}
