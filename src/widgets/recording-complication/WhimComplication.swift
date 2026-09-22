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
        if family == .accessoryInline { content }
        else { VStack(spacing: 2) { content }.font(.caption) }
    }
    @ViewBuilder private var content: some View {
        if let recording = entry.snapshot.activeRecording(at: entry.date) {
            Text(timerInterval: recording.createdAt...recording.createdAt.addingTimeInterval(recording.maximumDurationSeconds), countsDown: false)
                .monospacedDigit().accessibilityLabel("Whim recording elapsed time")
            if entry.snapshot.hasFailedNotes { Image(systemName: "exclamationmark.triangle.fill").accessibilityLabel("Failed Notes need attention") }
        } else if entry.snapshot.hasFailedNotes {
            Label("Whim", systemImage: "exclamationmark.triangle.fill").accessibilityLabel("Record a Whim. Failed Notes need attention")
        } else {
            Label("Whim", systemImage: "waveform").accessibilityLabel("Record a Whim")
        }
    }
}
