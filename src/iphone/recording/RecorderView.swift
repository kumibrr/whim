import SwiftUI
import WhimIPhone
struct RecorderView: View {
    var model: IPhoneModel
    @State private var confirm = false
    var body: some View {
        if let recording = model.recording {
            let remaining = max(0, recording.maximumDurationSeconds - floor(model.elapsedSeconds))
            let level = max(0, min(1, (model.peakPowerDBFS + 60) / 60))
            WhimContent {
                Text("Recording").whimTitle()
                Text(TimelineFormat.duration(seconds: model.elapsedSeconds)).font(.system(.largeTitle, design: .monospaced).bold()).monospacedDigit()
                RoundedRectangle(cornerRadius: 12).fill(Color.whimAccent).frame(height: 8 + level * 52).frame(height: 70)
                    .accessibilityLabel("Microphone level").accessibilityValue("\(Int((level * 100).rounded())) percent")
                ProgressView(value: min(model.elapsedSeconds, recording.maximumDurationSeconds), total: recording.maximumDurationSeconds).tint(.whimAccent)
                    .accessibilityLabel("Recording progress").accessibilityValue("\(TimelineFormat.duration(seconds: model.elapsedSeconds)) of \(TimelineFormat.duration(seconds: recording.maximumDurationSeconds))")
                Text(remaining <= recording.warningLeadSeconds ? "\(Int(remaining)) seconds remaining" : "Up to \(Int(recording.maximumDurationSeconds / 60)) minutes").foregroundStyle(remaining <= recording.warningLeadSeconds ? Color.red : .secondary)
                Text("Stop saves your Note and starts delivery.")
                Button("■ Stop") { Task { await model.stopRecording() } }.accessibilityLabel("Stop recording").accessibilityIdentifier("stop-recording")
                Button("Discard", role: .destructive) { confirm = true }.accessibilityLabel("Discard recording")
            }.disabled(model.isRecordingPending).accessibilityIdentifier("recorder-panel")
                .sheet(isPresented: $confirm) {
                    ConfirmationView(title: "Discard this Recording Session?", message: "This recording has not been saved. Discarding permanently removes it.", confirm: "Confirm discard", cancel: "Keep recording", error: model.error?.message, onCancel: { confirm = false }, onConfirm: { await model.discardRecording(); if model.error == nil { confirm = false } })
                        .presentationDetents([.medium, .large]).interactiveDismissDisabled(model.isRecordingPending)
                }
        }
    }
}
