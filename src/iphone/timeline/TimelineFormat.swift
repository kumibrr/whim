import Foundation
import WhimCore

public enum TimelineFormat {
    public static func duration(seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, seconds).rounded(.down)) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }
    public static func status(_ status: DeliveryStatus) -> String {
        switch status {
        case .setupRequired: "Setup required"
        case .queued: "Queued"
        case .sending: "Sending"
        case .sent: "✓ Sent"
        case .failed: "⚠ Failed"
        }
    }
    public static func date(_ date: Date) -> String { date.formatted(date: .numeric, time: .standard) }
    public static func source(_ source: CaptureSource) -> String { source == .iphone ? "iPhone" : "Apple Watch" }
}
