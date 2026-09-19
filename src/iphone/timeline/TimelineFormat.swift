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

public enum HistorySheetMotion {
    public static func openingReveal(translation: Double, height: Double) -> Double {
        guard translation.isFinite, height.isFinite, height > 0 else { return 0 }
        let distance = max(0, -translation)
        return min(height, distance / (1 + distance / (height * 2)))
    }

    public static func offset(
        isOpen: Bool,
        openingTranslation: Double,
        closingTranslation: Double,
        height: Double,
        safeAreaBottom: Double
    ) -> Double {
        guard height.isFinite, height > 0 else { return 0 }
        if isOpen { return max(0, closingTranslation.isFinite ? closingTranslation : 0) }
        let safeArea = safeAreaBottom.isFinite ? max(0, safeAreaBottom) : 0
        return height + safeArea - openingReveal(translation: openingTranslation, height: height)
    }
}

public enum HistoryScrollDismissal {
    public static func dragOffset(gestureBeganAtTop: Bool, translation: Double) -> Double {
        guard gestureBeganAtTop, translation.isFinite else { return 0 }
        return max(0, translation)
    }

    public static func shouldDismiss(
        gestureBeganAtTop: Bool,
        translation: Double,
        predictedTranslation: Double
    ) -> Bool {
        guard gestureBeganAtTop, translation.isFinite, predictedTranslation.isFinite else { return false }
        return translation > 100 || predictedTranslation > 200
    }
}
