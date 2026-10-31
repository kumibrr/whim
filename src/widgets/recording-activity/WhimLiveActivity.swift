import ActivityKit
import SwiftUI
import WidgetKit
import WhimCore

struct WhimLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            RecordingActivityView(state: context.state)
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
            RecordingWaveformControls(state: state)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop Whim Recording")
        .accessibilityHint("Stops recording and saves the Note")
    }
}

/// Fits below the timer and camera within the expanded Island's height budget.
/// Shared with the Lock Screen so both presentations render the published voice.
private struct RecordingWaveformControls: View {
    let state: RecordingActivityContent

    var body: some View {
        waveform(state)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.red)
                    .frame(width: 24, height: 24)
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
            }
            .contentShape(Rectangle())
            .accessibilityHidden(true)
    }
}

@MainActor private func waveform(_ state: RecordingActivityContent) -> some View {
    LiveWaveformSnapshotView(power: Double(state.power), tone: Double(state.tone))
}

struct RecordingActivityView: View {
    let state: RecordingActivityContent
    var stopIntent = StopWhimRecordingIntent()
    @Environment(\.activityFamily) private var family
    var body: some View {
        Button(intent: stopIntent) {
            VStack(alignment: .leading, spacing: 4) {
                timer(state.startedAt)
                    .font(family == .small ? .headline.monospacedDigit() : .title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
                RecordingWaveformControls(state: state)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel("Stop Whim Recording")
        .accessibilityValue(Text(timerInterval: state.startedAt...state.startedAt.addingTimeInterval(300), countsDown: false))
        .accessibilityHint("Stops recording and saves the Note")
    }
}
private func timer(_ startedAt: Date) -> some View {
    Text(timerInterval: startedAt...startedAt.addingTimeInterval(300), countsDown: false)
        .monospacedDigit().accessibilityLabel("Recording elapsed time")
}
