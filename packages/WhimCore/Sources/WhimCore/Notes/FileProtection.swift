import Foundation
import Darwin

public enum AudioProtection: Sendable { case unsent, delivered }

/// OS boundaries: tests may fail a real filesystem operation deterministically.
public protocol FileDurability: Sendable {
    func synchronizeFile(at url: URL) throws
    func protect(_ url: URL, as protection: AudioProtection) throws
    func synchronizeDirectory(at url: URL) throws
}

public struct SystemFileDurability: FileDurability {
    public init() {}

    public func synchronizeFile(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    public func protect(_ url: URL, as protection: AudioProtection) throws {
        #if os(iOS) || os(watchOS)
        let value: FileProtectionType = protection == .unsent ? .completeUntilFirstUserAuthentication : .complete
        try FileManager.default.setAttributes([.protectionKey: value], ofItemAtPath: url.path)
        #endif
    }

    public func synchronizeDirectory(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        if fsync(descriptor) != 0 && errno != EINVAL && errno != ENOTSUP {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
