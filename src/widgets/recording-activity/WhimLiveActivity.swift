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
                DynamicIslandExpandedRegion(.leading) {
                    Button(intent: StopWhimRecordingIntent()) {
                        timer(context.state.startedAt)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.red)
                            .padding(.leading, 12)
                            .padding(.top, 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Stops recording and saves the Note")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RecordingIslandExpandedView(state: context.state)
                }
            } compactLeading: {
                timer(context.state.startedAt)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.red)
                    .frame(width: 48)
            } compactTrailing: {
                waveform(context.state).frame(width: 32, height: 24)
            } minimal: {
                waveform(context.state).frame(width: 22, height: 22)
            }
            .widgetURL(URL(string: "whim://recording"))
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}
/// The whole expanded content, including its padding, is the Stop action.
struct RecordingIslandExpandedView: View {
    let state: RecordingActivityContent
    var stopIntent = StopWhimRecordingIntent()

    var body: some View {
        Button(intent: stopIntent) {
            waveform(state)
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .padding(.vertical, 12)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.red)
                        .frame(width: 24, height: 24)
                        .frame(width: 80, height: 80)
                        .background(.white.opacity(0.12), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
                }
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop Whim Recording")
        .accessibilityHint("Stops recording and saves the Note")
    }
}

@MainActor private func waveform(_ state: RecordingActivityContent) -> some View {
    LiveWaveformSnapshotView(power: Double(state.power), tone: Double(state.tone))
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
