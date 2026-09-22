import ActivityKit
import SwiftUI
import WidgetKit
import WhimCore

struct WhimLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            RecordingActivityView(startedAt: context.state.startedAt)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "whim://recording"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("Whim", systemImage: "waveform") }
                DynamicIslandExpandedRegion(.trailing) { timer(context.state.startedAt) }
                DynamicIslandExpandedRegion(.bottom) { stopButton }
            } compactLeading: {
                Image(systemName: "waveform").accessibilityLabel("Whim recording")
            } compactTrailing: {
                timer(context.state.startedAt).frame(width: 48)
            } minimal: {
                Image(systemName: "waveform").accessibilityLabel("Whim recording")
            }
            .widgetURL(URL(string: "whim://recording"))
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}
private struct RecordingActivityView: View {
    let startedAt: Date
    @Environment(\.activityFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Label("Whim", systemImage: "waveform"); Spacer(); timer(startedAt) }
            stopButton
        }
        .font(family == .small ? .caption : .body)
        .padding()
        .foregroundStyle(.white)
    }
}
private func timer(_ startedAt: Date) -> some View {
    Text(timerInterval: startedAt...startedAt.addingTimeInterval(300), countsDown: false)
        .monospacedDigit().accessibilityLabel("Recording elapsed time")
}
private var stopButton: some View {
    Button(intent: StopWhimRecordingIntent()) { Label("Stop", systemImage: "stop.fill") }
        .buttonStyle(.borderedProminent).tint(.red).accessibilityLabel("Stop Whim Recording")
}
