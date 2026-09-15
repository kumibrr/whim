import Foundation

/// WCSession delegate callbacks capture ordinary nonsecret state synchronously.
/// Keychain configuration context must bypass this durable inbox entirely.
public struct ConnectivityInbox: Sendable {
    private let journal: ConnectivityJournal
    public init(databaseURL: URL) throws { journal = try ConnectivityJournal(databaseURL: databaseURL) }
    public func capture(_ data: Data) throws {
        let envelope = try ConnectivityEnvelope.decode(data)
        if case .configuration = envelope.payload { throw ConnectivityError.invalidConfiguration }
        try journal.append(envelope)
    }
}
