import SwiftUI
import WidgetKit
import WhimCore

enum WhimCornerPosition: String, CaseIterable {
    case topRight, topLeft, bottomRight, bottomLeft

    var widgetKind: String {
        switch self {
        case .topRight: ComplicationWidgetKind.recording.rawValue
        case .topLeft: ComplicationWidgetKind.topLeft.rawValue
        case .bottomRight: ComplicationWidgetKind.bottomRight.rawValue
        case .bottomLeft: ComplicationWidgetKind.bottomLeft.rawValue
        }
    }
}

struct WhimComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: ComplicationSnapshot
    var corner: WhimCornerPosition = .topRight
}
struct WhimComplicationProvider: TimelineProvider {
    var corner: WhimCornerPosition = .topRight
    var loadSnapshot: @Sendable () throws -> ComplicationSnapshot = {
        try ComplicationStore(url: WhimProductionComposition.sharedRoot()
            .appendingPathComponent("complication.json")).load()
    }

    func placeholder(in context: Context) -> WhimComplicationEntry {
        .init(date: Date(), snapshot: .idle, corner: corner)
    }
    func getSnapshot(in context: Context, completion: @escaping (WhimComplicationEntry) -> Void) {
        completion(entries(at: Date())[0])
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WhimComplicationEntry>) -> Void) {
        completion(Timeline(entries: entries(at: Date()), policy: .never))
    }
    func entries(at date: Date) -> [WhimComplicationEntry] {
        let snapshot = (try? loadSnapshot()) ?? .idle
        let current = WhimComplicationEntry(date: date, snapshot: snapshot, corner: corner)
        var entries = [current]
        if let recording = current.snapshot.activeRecording(at: current.date) {
            entries.append(.init(date: recording.createdAt.addingTimeInterval(recording.maximumDurationSeconds),
                                 snapshot: .init(recording: nil, hasFailedNotes: current.snapshot.hasFailedNotes),
                                 corner: corner))
        }
        return entries
    }
}
struct WhimComplication: Widget {
    static let supportedFamilies: [WidgetFamily] = [.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline]
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WhimCornerPosition.topRight.widgetKind,
                            provider: WhimComplicationProvider(corner: .topRight)) { entry in
            WhimComplicationView(entry: entry)
        }
        .configurationDisplayName("Record a Whim")
        .description("Start recording. For Corner slots, choose the entry matching its position on the face.")
        .supportedFamilies(Self.supportedFamilies)
    }
}
struct WhimTopLeftComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WhimCornerPosition.topLeft.widgetKind,
                            provider: WhimComplicationProvider(corner: .topLeft)) { entry in
            WhimComplicationView(entry: entry)
        }
        .configurationDisplayName("Record top left")
        .description("Start recording. For Corner slots, choose the entry matching its position on the face.")
        .supportedFamilies([.accessoryCorner])
    }
}
struct WhimBottomRightComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WhimCornerPosition.bottomRight.widgetKind,
                            provider: WhimComplicationProvider(corner: .bottomRight)) { entry in
            WhimComplicationView(entry: entry)
        }
        .configurationDisplayName("Record bottom right")
        .description("Start recording. For Corner slots, choose the entry matching its position on the face.")
        .supportedFamilies([.accessoryCorner])
    }
}
struct WhimBottomLeftComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WhimCornerPosition.bottomLeft.widgetKind,
                            provider: WhimComplicationProvider(corner: .bottomLeft)) { entry in
            WhimComplicationView(entry: entry)
        }
        .configurationDisplayName("Record bottom left")
        .description("Start recording. For Corner slots, choose the entry matching its position on the face.")
        .supportedFamilies([.accessoryCorner])
    }
}
private struct WhimComplicationView: View {
    let entry: WhimComplicationEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        WhimComplicationContent(entry: entry, family: family)
            .widgetURL(URL(string: "whim://record"))
            .containerBackground(.black, for: .widget)
    }
}
struct WhimComplicationContent: View {
    let entry: WhimComplicationEntry
    let family: WidgetFamily
    var body: some View {
        switch family {
        case .accessoryInline: content
        case .accessoryCircular: circular
        case .accessoryCorner: WhimCornerComplicationContent(entry: entry)
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

struct WhimCornerComplicationContent: View {
    let entry: WhimComplicationEntry
    var imageBundle: Bundle = .main

    private var displaysLogo: Bool {
        entry.snapshot.activeRecording(at: entry.date) == nil && !entry.snapshot.hasFailedNotes
    }

    var body: some View {
        glyph
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: displaysLogo ? .center : .bottom)
            .widgetAccentable()
            .widgetCurvesContent(!displaysLogo)
            .widgetLabel { WhimCornerComplicationLabel(entry: entry) }
    }

    @ViewBuilder private var glyph: some View {
        if entry.snapshot.activeRecording(at: entry.date) != nil {
            Image(systemName: "stop.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(.red)
                .accessibilityLabel("Whim recording")
        } else if entry.snapshot.hasFailedNotes {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.monochrome)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18, alignment: .bottom)
                .foregroundStyle(.white)
                .accessibilityLabel("Record a Whim. Failed Notes need attention")
        } else {
            WhimCornerLogo(imageBundle: imageBundle)
                .frame(maxWidth: 21)
                .accessibilityLabel("Record a Whim")
        }
    }
}

// Render the compact mark normally so it remains straight and visible.
// The separate widget label follows the bezel in each corner.
struct WhimCornerLogo: View {
    var imageBundle: Bundle = .main

    var body: some View {
        Image("whim.small.symbol", bundle: imageBundle)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 38, maxHeight: 11)
            .accessibilityLabel("Whim")
    }
}

// WidgetKit places this label on the dial's inner curve and gives the outer
// glyph its own space. Keep it separate from Circular's stacked presentation.
struct WhimCornerComplicationLabel: View {
    let entry: WhimComplicationEntry

    @ViewBuilder var body: some View {
        if entry.snapshot.activeRecording(at: entry.date) == nil && !entry.snapshot.hasFailedNotes {
            label
        } else {
            label.baselineOffset(14)
        }
    }

    @ViewBuilder private var label: some View {
        if let recording = entry.snapshot.activeRecording(at: entry.date) {
            let timer = Text(timerInterval: recording.createdAt...recording.createdAt.addingTimeInterval(recording.maximumDurationSeconds), countsDown: false)
            if entry.snapshot.hasFailedNotes {
                (Text(Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.monochrome)) + Text(" ") + timer)
                    .monospacedDigit()
                    .accessibilityLabel("Whim recording elapsed time. Failed Notes need attention")
                    .accessibilityValue(timer)
            } else {
                timer.monospacedDigit()
                    .accessibilityLabel("Whim recording elapsed time")
                    .accessibilityValue(timer)
            }
        } else {
            Text(entry.snapshot.hasFailedNotes ? "Check Notes" : "Record")
        }
    }
}
