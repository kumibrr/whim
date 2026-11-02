import Foundation

/// Presentation routing from the platform's hardware identifier. Unknown devices
/// retain the universally available control guide rather than a guessed capability.
public enum QuickCaptureGuide {
    public static func mediaName(route: Route, isWatch: Bool, page: Int) -> String? {
        guard route == .actionButton, !isWatch, (0...1).contains(page) else { return nil }
        return ["action-button-preview", "action-button-setup"][page]
    }


    public static func needsUpgradeGuide(onboardingCompleted: Bool, acknowledged: Bool) -> Bool {
        onboardingCompleted && !acknowledged
    }

    /// Nil means onboarding is complete; Watch setup is its own optional step.
    public static func nextSetupStep(after step: Int, hasPairedWatch: Bool) -> Int? {
        step == 3 && hasPairedWatch ? 4 : nil
    }
    public enum Route: String, Sendable { case actionButton, lockScreen }
    public static func route(for model: String) -> Route {
        let supported: Set<String> = [
            "iPhone16,1", "iPhone16,2", // 15 Pro
            "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4", "iPhone17,5", // 16
            "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4", "iPhone18,5", // 17 / Air
            "iPhone19,2", "iPhone19,3" // 18 Pro; identifiers from Apple's simulator profiles
        ]
        return supported.contains(model) ? .actionButton : .lockScreen
    }
    public static var currentRoute: Route {
        #if targetEnvironment(simulator)
        return route(for: ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "")
        #else
        var value = utsname()
        uname(&value)
        let model = withUnsafeBytes(of: &value.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return route(for: model)
        #endif
    }
}
