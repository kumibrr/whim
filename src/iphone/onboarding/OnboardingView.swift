import SwiftUI
import WhimCore
import WhimIPhone
struct OnboardingView: View {
    var model: IPhoneModel
    let settings: SettingsProjection?
    @State private var step = 0
    var body: some View {
        WhimContent {
            Text(step == 0 ? "A place for your thoughts" : step == 1 ? "Your workflow, directly" : "Ready when inspiration strikes").whimTitle()
            if step == 0 {
                Text("Whim stores voice Notes locally on your iPhone and Apple Watch and delivers them directly to your webhook. No account, cloud storage, or analytics.")
                Button("Get started") { step = 1 }
            } else if step == 1 {
                if let settings { WebhookConfigurationView(model: model, configuration: settings.webhook) }
                else { ProgressView("Loading webhook settings…") }
                Button("Continue to microphone") { step = 2 }
                Button("Skip webhook setup") { step = 2 }
            } else {
                Text("Allow microphone access to capture voice Notes. You can finish setup and change permissions later in Settings.")
                if model.startupState?.microphone == .notDetermined {
                    Button("Allow microphone") { complete(request: true) }
                }
                if model.startupState?.microphone == .denied || model.startupState?.microphone == .restricted {
                    Text("Microphone access is denied. Enable it in system settings.").foregroundStyle(.red)
                    Button("Open system settings") { Task { await model.perform { try await model.client.openSystemSettings() } } }
                }
                Button(model.startupState?.microphone == .granted ? "Start using Whim" : "Continue without microphone") { complete(request: false) }
            }
        }.disabled(model.isPending || !model.captureReady).accessibilityIdentifier("onboarding")
    }
    private func complete(request: Bool) {
        Task { await model.perform {
            if request { _ = try await model.client.requestPermission(.microphone) }
            try await model.client.completeOnboarding()
        } }
    }
}
