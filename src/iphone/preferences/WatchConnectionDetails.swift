import Foundation
import WhimCore

public struct SynchronizationTechnicalRow: Equatable, Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let value: String
    public init(_ label: String, _ value: String) { self.label = label; self.value = value }
}

public struct WatchConnectionDetails: Sendable {
    public let cause: String?
    public let recovery: String?
    public let technicalRows: [SynchronizationTechnicalRow]
    public init(settings: WatchSettingsProjection) {
        let facts = settings.connectionDetails
        if settings.availability == "available" {
            cause = nil; recovery = nil
        } else {
            switch settings.availabilityReason {
            case "unsupported":
                cause = "Watch synchronization is not supported on this device."
                recovery = "You can keep recording Notes on this iPhone."
            case "unpaired":
                cause = "No Apple Watch is paired with this iPhone."
                recovery = "Open the Watch app on this iPhone to pair your Apple Watch, then open Whim on both devices."
            case "appNotInstalled":
                cause = "iOS reports that Whim is not installed on your Apple Watch."
                recovery = "Check or complete Whim’s installation in the Watch app on this iPhone, then open Whim on your Watch."
            case "inactive":
                if let failure = facts?.activationFailure {
                    cause = "iOS could not start the Watch connection. " + synchronizationErrorLabel(failure)
                    switch failure.category {
                    case "deviceNotPaired": recovery = "Open the Watch app on this iPhone to pair your Apple Watch, then refresh status."
                    case "watchAppNotInstalled": recovery = "Check or complete Whim’s installation in the Watch app on this iPhone, then open Whim on your Watch."
                    case "sessionNotSupported": recovery = "You can keep recording Notes on this iPhone."
                    case "storageFull": recovery = "Check available storage on both devices, then reopen Whim and refresh status."
                    default: recovery = "Close and reopen Whim on both devices, then refresh status."
                    }
                } else {
                    cause = "The connection to your Apple Watch has not started yet."
                    recovery = "Open Whim on both devices, then refresh status."
                }
            default:
                cause = "Whim cannot determine why Watch synchronization is unavailable."
                recovery = "Open Whim on both devices, then refresh status."
            }
        }
        func yesNo(_ value: Bool?) -> String { value.map { $0 ? "Yes" : "No" } ?? "Not reported" }
        let activation = facts?.activationState.map {
            switch $0 { case "activated": "Activated"; case "inactive": "Inactive"; default: "Not activated" }
        } ?? "Not reported"
        technicalRows = [
            .init("Watch Connectivity supported", yesNo(facts?.supported)),
            .init("Activation", activation),
            .init("Watch paired", yesNo(facts?.paired)),
            .init("Whim installed on Watch", yesNo(facts?.counterpartAppInstalled)),
            .init("Immediately reachable", yesNo(facts?.reachable)),
            .init("Queued state transfers", facts?.pendingStateTransfers.map(String.init) ?? "Not reported"),
            .init("Queued audio transfers", facts?.pendingAudioTransfers.map(String.init) ?? "Not reported"),
            .init("Last synchronized", settings.lastSynchronizedAt.map(TimelineFormat.date) ?? "Not reported")
        ] + synchronizationErrorRows(facts?.activationFailure, prefix: "Activation")
          + synchronizationErrorRows(facts?.lastTransferFailure, prefix: "Last transfer")
    }
}

public func synchronizationErrorLabel(_ error: SynchronizationSystemError) -> String {
    switch error.category {
    case "sessionNotSupported": "Watch Connectivity is not supported."
    case "sessionNotActivated", "sessionInactive": "The connection is inactive."
    case "deviceNotPaired": "No Watch is paired."
    case "watchAppNotInstalled": "Whim is not installed on Watch."
    case "companionAppNotInstalled": "Whim is not installed on iPhone."
    case "notReachable": "The paired device could not be reached immediately."
    case "transferTimedOut", "replyTimedOut": "The transfer timed out."
    case "storageFull": "The system reported insufficient storage."
    case "fileAccessDenied": "The system could not access the audio file."
    case "deliveryFailed", "messageReplyFailed": "The system could not complete the transfer."
    case "payloadTooLarge": "The transfer exceeded the system size limit."
    case "invalidParameter", "unsupportedPayload", "sessionMissingDelegate", "watchOnlyApp": "The system rejected the connection or transfer configuration."
    default: "The system did not report a known cause."
    }
}
public func synchronizationErrorRows(_ error: SynchronizationSystemError?, prefix: String) -> [SynchronizationTechnicalRow] {
    guard let error else { return [] }
    var rows: [SynchronizationTechnicalRow] = [.init("\(prefix) error", synchronizationErrorLabel(error))]
    if let domain = error.domain { rows.append(.init("\(prefix) error domain", domain)) }
    if let code = error.code { rows.append(.init("\(prefix) error code", String(code))) }
    rows.append(.init("\(prefix) error observed", error.observedAt.map(TimelineFormat.date) ?? "Not reported"))
    return rows
}
