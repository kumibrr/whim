import Foundation
import UserNotifications

public protocol DeliveryNotificationAdapter: Sendable {
    func notifyFailure(title: String, reason: String, noteID: NoteID) async
    func cancelAll() async
}

public extension DeliveryNotificationAdapter {
    func cancelAll() async {}
}

public struct LocalNotificationAdapter: DeliveryNotificationAdapter {
    public init() {}

    public func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    public func notifyFailure(title: String, reason: String, noteID: NoteID) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = reason
        content.userInfo = ["note_id": noteID.rawValue.uuidString.lowercased()]
        let request = UNNotificationRequest(identifier: "whim-delivery-\(noteID.rawValue.uuidString.lowercased())",
            content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
