import SwiftUI
import WhimIPhone

/// Uses the onboarding frame with release-selected native content and optional settings.
struct AppUpdateView: View {
    @Bindable var model: AppUpdateModel
    let update: AppUpdate

    var body: some View {
        OnboardingFrame(step: 0, showsProgress: false) {
            VStack(alignment: .leading, spacing: 32) {
                OnboardingHeading(title: update.title, detail: update.detail)
                ForEach(Array(update.sections.enumerated()), id: \.offset) { _, section in
                    content(section)
                }
                if let error = model.error {
                    WhimErrorText(message: error.message)
                    if model.editor == nil {
                        Button("Try again") { Task { await model.load() } }
                            .buttonStyle(OnboardingSecondaryButtonStyle())
                    }
                }
            }
        } actions: {
            Button("Continue") { Task { await model.complete() } }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(update.hasPreferenceControls && model.editor == nil)
                .accessibilityIdentifier("app-update-continue")
            Button("Skip for now") { model.skip() }
                .buttonStyle(OnboardingSecondaryButtonStyle())
                .accessibilityIdentifier("app-update-skip")
        }
        .disabled(model.isPending)
        .task { await model.load() }
        .interactiveDismissDisabled()
        .presentationDetents([.large])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-update-sheet")
    }

    @ViewBuilder private func content(_ section: AppUpdate.Section) -> some View {
        switch section {
        case .information(let title, let detail):
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(detail).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .quickCaptureGuide:
            QuickCaptureSetupView()
        case .onDeviceTitles:
            if let editor = model.editor {
                VStack(alignment: .leading, spacing: 12) {
                    OnDeviceTitlesControl(editor: editor)
                    Text("Only on-device recognition is used. No full transcript is stored.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else if model.error == nil { ProgressView("Loading title settings…") }
        case .audioRetention:
            if let editor = model.editor {
                VStack(alignment: .leading, spacing: 12) {
                    AudioRetentionControl(editor: editor)
                    Text("Unsent and recovered Notes are always kept until you delete them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else if model.error == nil { ProgressView("Loading audio settings…") }
        }
    }
}
