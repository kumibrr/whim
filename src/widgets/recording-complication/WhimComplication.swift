import SwiftUI
import WidgetKit
import WhimCore

struct WhimComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: ComplicationSnapshot
}
struct WhimComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WhimComplicationEntry { .init(date: Date(), snapshot: .idle) }
    func getSnapshot(in context: Context, completion: @escaping (WhimComplicationEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WhimComplicationEntry>) -> Void) {
        let current = entry()
        var entries = [current]
        if let recording = current.snapshot.activeRecording(at: current.date) {
            entries.append(.init(date: recording.createdAt.addingTimeInterval(recording.maximumDurationSeconds), snapshot: .init(recording: nil, hasFailedNotes: current.snapshot.hasFailedNotes)))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
    private func entry() -> WhimComplicationEntry {
        let snapshot = try? ComplicationStore(url: WhimProductionComposition.sharedRoot().appendingPathComponent("complication.json")).load()
        return .init(date: Date(), snapshot: snapshot ?? .idle)
    }
}
struct WhimComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.whim.recording", provider: WhimComplicationProvider()) { entry in
            WhimComplicationView(entry: entry)
                .widgetURL(URL(string: "whim://record"))
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Record a Whim")
        .description("Start recording. See recording time and Notes needing attention.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
private struct WhimComplicationView: View {
    let entry: WhimComplicationEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        switch family {
        case .accessoryInline: content
        case .accessoryCircular: circular
        default: VStack(spacing: 2) { content }.font(.caption)
        }
    }
    // The small circle has no room for the full mark or caption-sized digits, so it
    // shows the compact mark, or the elapsed time above the Watch app's Stop glyph.
    @ViewBuilder private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let recording = entry.snapshot.activeRecording(at: entry.date) {
                VStack(spacing: 3) {
                    elapsed(recording)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .minimumScaleFactor(0.6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.red)
                        .frame(width: 14, height: 14)
                        .widgetAccentable()
                        .accessibilityLabel("Stop recording")
                }
                .padding(.horizontal, 6)
            } else {
                Image("whim.small")
                    .resizable()
                    .scaledToFit()
                    // The stroke's round caps reach the artwork's edges, so the tips meet the rim.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .widgetAccentable()
                    .accessibilityLabel("Record a Whim")
            }
            if entry.snapshot.hasFailedNotes {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 4)
                    .accessibilityLabel("Failed Notes need attention")
            }
        }
    }
    private func elapsed(_ recording: RecordingProjection) -> some View {
        Text(timerInterval: recording.createdAt...recording.createdAt.addingTimeInterval(recording.maximumDurationSeconds), countsDown: false)
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .accessibilityLabel("Whim recording elapsed time")
    }
    @ViewBuilder private var content: some View {
        if let recording = entry.snapshot.activeRecording(at: entry.date) {
            elapsed(recording)
            if entry.snapshot.hasFailedNotes { Image(systemName: "exclamationmark.triangle.fill").accessibilityLabel("Failed Notes need attention") }
        } else if entry.snapshot.hasFailedNotes {
            Label("Whim", systemImage: "exclamationmark.triangle.fill").accessibilityLabel("Record a Whim. Failed Notes need attention")
        } else {
            Label("Whim", image: "whim.waveform").accessibilityLabel("Record a Whim")
        }
    }
}
