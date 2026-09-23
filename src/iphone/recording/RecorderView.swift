import SwiftUI
import WhimCore
import WhimIPhone

struct CaptureHomeView: View {
    var model: IPhoneModel
    var glassNamespace: Namespace.ID
    var settings: () -> Void
    var body: some View {
        VStack {
            HStack {
                if model.areFailuresCollapsed {
                    ErrorNotificationsButton(model: model)
                }
                Spacer()
                Button(action: settings) {
                    Image(systemName: "gearshape").font(.system(size: 20, weight: .regular))
                        .frame(width: 48, height: 48).whimGlass(in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Settings")
                    .accessibilityIdentifier("settings-button")
            }.padding(.horizontal, 24).padding(.top, 12)
            Spacer()
            if !model.feedback.isEmpty {
                Text(model.feedback).font(.footnote).foregroundStyle(.secondary).padding(
                    .bottom, 20)
            }
            Button {
                Task { await model.startRecording() }
            } label: {
                Circle().fill(.white).frame(width: 26, height: 26)
                    .frame(width: 80, height: 80).whimGlass(in: Circle())
                    .captureGlassIdentity("capture", in: glassNamespace)
            }.buttonStyle(.plain).accessibilityLabel("Record a Whim")
                .accessibilityIdentifier("record-button")
                .disabled(model.isRecordingPending || !model.captureReady)
            if !model.captureReady { ProgressView("Preparing recording…") }
            Button {
                model.openHistory()
            } label: {
                VStack(spacing: 10) {
                    Text("scroll to see previous notes.").font(.system(size: 12))
                    Image(systemName: "chevron.up").font(
                        .system(size: 9, weight: .semibold))
                }.foregroundStyle(.white.opacity(0.5)).padding(.top, 22).padding(
                    .bottom, 12
                )
                .frame(minHeight: 48)
            }.buttonStyle(.plain).accessibilityLabel("Show previous Notes")
                .accessibilityIdentifier("history-hint")
        }.accessibilityElement(children: .contain).accessibilityIdentifier("whim-home")
    }
}

struct RecorderView: View {
    var model: IPhoneModel
    var glassNamespace: Namespace.ID
    var body: some View {
        if let recording = model.recording {
            let remaining = max(0, recording.maximumDurationSeconds - floor(model.elapsedSeconds))
            VStack(spacing: 12) {
                Text("RECORDING").font(.system(size: 11, weight: .medium)).tracking(3)
                    .foregroundStyle(.secondary).padding(.top, 32)
                Text(TimelineFormat.duration(seconds: model.elapsedSeconds))
                    .font(.system(size: 32, weight: .light, design: .monospaced))
                    .monospacedDigit()
                ProgressView(
                    value: min(model.elapsedSeconds, recording.maximumDurationSeconds),
                    total: recording.maximumDurationSeconds
                )
                .tint(.white).frame(width: 100)
                .accessibilityLabel("Recording progress")
                .accessibilityValue(
                    "\(TimelineFormat.duration(seconds: model.elapsedSeconds)) of \(TimelineFormat.duration(seconds: recording.maximumDurationSeconds))"
                )
                if remaining <= recording.warningLeadSeconds {
                    Text("\(Int(remaining)) seconds remaining").font(.footnote)
                }
                Spacer()
                Text("Stop saves your Note and starts delivery.").font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 24).padding(
                        .bottom, 8)
                Button {
                    Task { await model.stopRecording() }
                } label: {
                    RoundedRectangle(cornerRadius: 5).fill(.red).frame(
                        width: 24, height: 24
                    )
                    .frame(width: 80, height: 80).whimGlass(in: Circle())
                    .captureGlassIdentity("capture", in: glassNamespace)
                }.buttonStyle(.plain).accessibilityLabel("Stop recording")
                    .accessibilityIdentifier("stop-recording")
                Button(role: .destructive) {
                    Task { await model.discardRecording() }
                } label: {
                    if #available(iOS 26, *) {
                        discardLabel.whimGlass(in: Capsule())
                            .captureGlassIdentity("discard", in: glassNamespace)
                    } else {
                        discardLabel
                    }
                }.buttonStyle(.plain).accessibilityLabel("Discard recording")
                    .accessibilityIdentifier("discard-recording")
                    .padding(.bottom, 12)
            }.frame(maxWidth: .infinity).overlay(alignment: .topLeading) {
                if model.areFailuresCollapsed {
                    ErrorNotificationsButton(model: model).padding(.leading, 24).padding(.top, 12)
                }
            }.disabled(model.isRecordingPending).accessibilityElement(children: .contain)
                .accessibilityIdentifier("recorder-panel")
        }
    }
    private var discardLabel: some View {
        Text("Discard")
            .font(.body.weight(.semibold))
            .foregroundStyle(.red)
            .frame(minWidth: 120, minHeight: 56)
            .contentShape(Rectangle())
    }
}

private struct ErrorNotificationsButton: View {
    var model: IPhoneModel
    var body: some View {
        Button { model.expandFailures() } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                Text("\(model.failureCount)").monospacedDigit()
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, 14).frame(minHeight: 48)
            .whimGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.failureCount == 1 ? "1 notification" : "\(model.failureCount) notifications")
        .accessibilityHint("Show error details")
        .accessibilityIdentifier("error-notifications")
    }
}
