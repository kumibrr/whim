import Foundation

/// Authenticated Watch Connectivity is the system boundary. Immediate reachability
/// never gates durable delivery; it only routes a user's explicit Sync now.
public protocol PeerTransport: Sendable {
    var isAvailable: Bool { get }
    var isActivated: Bool { get }
    var isReachable: Bool { get }
    func activate(receive: @escaping @Sendable (PeerEvent) -> Void)
    func completeReceivedFile(_ url: URL) throws
    func transfer(_ envelope: ConnectivityEnvelope) throws
    func transferFile(at url: URL, metadata: ConnectivityEnvelope) throws
    func updateContext(_ envelope: ConnectivityEnvelope, credentials: StoredWebhookCredentials?) throws
}

public enum PeerEvent: Sendable {
    case activated
    case message(ConnectivityEnvelope)
    case file(URL, ConnectivityEnvelope)
    case configuration(ConnectivityEnvelope, StoredWebhookCredentials)
    case transferFailed(UUID)
}

public extension PeerTransport {
    var isReachable: Bool { false }
    func completeReceivedFile(_ url: URL) throws {}
}
