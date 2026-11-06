import Foundation

/// Presentation routing from the platform's hardware identifier. Control Center
/// and Lock Screen setup are hidden until their guides are ready.
public enum QuickCaptureGuide {
    public static func mediaName(route: Route?, isWatch: Bool, page: Int) -> String? {
        guard route == .actionButton, !isWatch, (0...1).contains(page) else { return nil }
        return ["action-button-preview", "action-button-setup"][page]
    }


    public static func needsUpgradeGuide(onboardingCompleted: Bool, acknowledged: Bool, route: Route? = currentRoute) -> Bool {
        route != nil && onboardingCompleted && !acknowledged
    }

    public static func onboardingStep(saved: Int, setupOnly: Bool, route: Route? = currentRoute) -> Int {
        let lastStep = route == nil ? 2 : 3
        return setupOnly ? lastStep : min(lastStep, max(0, saved))
    }

    /// Watch onboarding is deferred until its demonstration video is ready.
    public static func nextSetupStep(after step: Int, hasPairedWatch: Bool) -> Int? {
        nil
    }
    public enum Route: String, Sendable { case actionButton, lockScreen }
    public static func route(for model: String) -> Route? {
        let supported: Set<String> = [
            "iPhone16,1", "iPhone16,2", // 15 Pro
            "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4", "iPhone17,5", // 16
            "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4", "iPhone18,5", // 17 / Air
            "iPhone19,2", "iPhone19,3" // 18 Pro; identifiers from Apple's simulator profiles
        ]
        return supported.contains(model) ? .actionButton : nil
    }
    public static var currentRoute: Route? {
        #if targetEnvironment(simulator)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-WhimFixtureDeviceModel"), arguments.indices.contains(index + 1) {
            return route(for: arguments[index + 1])
        }
        #endif
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
