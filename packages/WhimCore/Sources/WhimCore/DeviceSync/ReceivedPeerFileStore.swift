import Foundation

/// Synchronous ownership at WCSession's temporary-file lifetime boundary. Metadata
/// is durable before moving audio, so process termination cannot orphan its identity.
public struct ReceivedPeerFileStore: Sendable {
    private let root: URL
    private let durability: any FileDurability
    public init(root: URL, durability: any FileDurability = SystemFileDurability()) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root.resolvingSymlinksInPath(); self.durability = durability
        try durability.protect(root, as: .unsent)
    }
    public struct Pending: Sendable { public let url: URL; public let metadata: Data }
    public func takeOwnership(of ephemeral: URL, metadata: Data) throws -> URL {
        let envelope = try ConnectivityEnvelope.decode(metadata)
        guard case .noteMetadata = envelope.payload else { throw ConnectivityError.invalidFile }
        let directory = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sidecar = directory.appendingPathComponent("envelope.plist")
        try metadata.write(to: sidecar, options: .atomic)
        try durability.protect(sidecar, as: .unsent)
        try durability.synchronizeFile(at: sidecar)
        try durability.synchronizeDirectory(at: directory)
        try durability.synchronizeDirectory(at: root)
        let audio = directory.appendingPathComponent("audio.m4a")
        try FileManager.default.moveItem(at: ephemeral, to: audio)
        try durability.protect(audio, as: .unsent)
        try durability.synchronizeFile(at: audio)
        try durability.synchronizeDirectory(at: directory)
        return audio
    }
    public func pending() throws -> [Pending] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { directory in
            let audio = directory.appendingPathComponent("audio.m4a")
            guard FileManager.default.fileExists(atPath: audio.path) else { return nil }
            let metadata = try Data(contentsOf: directory.appendingPathComponent("envelope.plist"))
            _ = try ConnectivityEnvelope.decode(metadata)
            return Pending(url: audio, metadata: metadata)
        }
    }
    public func complete(_ url: URL) throws {
        let directory = url.deletingLastPathComponent().resolvingSymlinksInPath()
        guard directory.deletingLastPathComponent().path == root.resolvingSymlinksInPath().path else { return }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try durability.synchronizeDirectory(at: root)
    }
}
