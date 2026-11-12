import Foundation

/// Authenticated Watch Connectivity is the system boundary. Immediate reachability
/// is deliberately absent from this contract: it never gates durable delivery.
public protocol PeerTransport: Sendable {
    var isAvailable: Bool { get }
    var isActivated: Bool { get }
    /// Why `isAvailable` is false, when the system can tell. Nil while available or unknown.
    var unavailabilityReason: PeerUnavailabilityReason? { get }
    var connectionDetails: PeerConnectionDetails? { get }
    func activate(receive: @escaping @Sendable (PeerEvent) -> Void)
    func completeReceivedFile(_ url: URL) throws
    func transfer(_ envelope: ConnectivityEnvelope) throws
    func transferFile(at url: URL, metadata: ConnectivityEnvelope) throws
    func updateContext(_ envelope: ConnectivityEnvelope, credentials: StoredWebhookCredentials?) throws
}

public enum PeerEvent: Sendable {
    case activated
    case statusChanged
    case message(ConnectivityEnvelope)
    case file(URL, ConnectivityEnvelope)
    case configuration(ConnectivityEnvelope, StoredWebhookCredentials)
    case transferFailed(UUID)
}

/// What keeps the paired device out of reach. "Unavailable" alone gives the user nothing
/// to act on: a Watch app that iOS does not list as installed looks the same as no Watch.
public enum PeerUnavailabilityReason: String, Codable, Sendable {
    case inactive, unpaired, appNotInstalled, unsupported

    /// `paired` is nil on Apple Watch, which cannot run unpaired.
    public static func resolve(activated: Bool, paired: Bool?, counterpartInstalled: Bool) -> Self? {
        if !activated { return .inactive }
        if paired == false { return .unpaired }
        return counterpartInstalled ? nil : .appNotInstalled
    }
}

public extension PeerTransport {
    var connectionDetails: PeerConnectionDetails? { nil }
    var unavailabilityReason: PeerUnavailabilityReason? { nil }
    func completeReceivedFile(_ url: URL) throws {}
}
