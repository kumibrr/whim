import Foundation
import AVFoundation
import UserNotifications
#if canImport(Speech) && !os(watchOS)
import Speech
#endif
#if os(iOS)
import UIKit
#endif

public enum PermissionKind: String, Codable, Sendable { case microphone, speech, notifications }
public enum PermissionStatus: String, Codable, Sendable { case notDetermined = "not_determined", granted, denied, restricted, unavailable }
public protocol PermissionAdapter: Sendable {
    func status(_ kind: PermissionKind) async -> PermissionStatus
    func request(_ kind: PermissionKind) async throws -> PermissionStatus
    func openSettings() async throws
}
public struct PermissionProjection: Codable, Equatable, Sendable {
    public let microphone: PermissionStatus
    public let speech: PermissionStatus
    public let notifications: PermissionStatus
}
public struct SystemPermissionAdapter: PermissionAdapter {
    public init() {}
    public func status(_ kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .microphone:
            #if os(iOS) || os(watchOS)
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            default: return .notDetermined
            }
            #else
            return .unavailable
            #endif
        case .speech:
            #if canImport(Speech) && !os(watchOS)
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .denied: return .denied
            case .restricted: return .restricted
            default: return .notDetermined
            }
            #else
            return .unavailable
            #endif
        case .notifications:
            #if os(iOS) || os(watchOS)
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .authorized, .provisional, .ephemeral: return .granted
            case .denied: return .denied
            default: return .notDetermined
            }
            #else
            return .unavailable
            #endif
        }
    }
    public func request(_ kind: PermissionKind) async throws -> PermissionStatus {
        guard await status(kind) == .notDetermined else { return await status(kind) }
        switch kind {
        case .microphone:
            #if os(iOS) || os(watchOS)
            _ = await AVAudioApplication.requestRecordPermission()
            #endif
        case .speech:
            #if canImport(Speech) && !os(watchOS)
            await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() } }
            #endif
        case .notifications:
            #if os(iOS) || os(watchOS)
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            #endif
        }
        return await status(kind)
    }
    @MainActor public func openSettings() async throws {
        #if os(iOS)
        let opened = await UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        if !opened { throw WhimServiceError.setupRequired("System settings could not open.") }
        #else
        throw WhimServiceError.setupRequired("Open Settings on your iPhone.")
        #endif
    }
}
