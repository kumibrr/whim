import SwiftUI
import WidgetKit
import WhimCore
#if os(watchOS)
import WatchKit
#endif

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
        if displaysLogo {
            WhimCornerIdleContent(corner: entry.corner, imageBundle: imageBundle)
                .widgetAccentable()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Record a Whim")
        } else {
            glyph
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .widgetAccentable()
                .widgetCurvesContent()
                .widgetLabel { WhimCornerComplicationLabel(entry: entry) }
        }
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
                .accessibilityLabel("Record a Whim")
        }
    }
}

// WidgetKit's text/image template offsets these two elements. Render the idle
// mark and curved caption together so both share one measured radial axis.
struct WhimCornerIdleContent: View {
    var corner: WhimCornerPosition = .topRight
    var imageBundle: Bundle = .main

    private var screenAspectRatio: CGFloat {
        #if os(watchOS)
        let bounds = WKInterfaceDevice.current().screenBounds
        return bounds.width / bounds.height
        #else
        return 176.0 / 215.0
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let top = corner == .topRight || corner == .topLeft
            let right = corner == .topRight || corner == .bottomRight
            let angle = (top == right ? 1.0 : -1.0) * atan(screenAspectRatio)
            let outward = CGVector(dx: (right ? 1 : -1) * abs(sin(angle)),
                                   dy: (top ? -1 : 1) * cos(angle))
            let tangent = CGVector(dx: cos(angle), dy: sin(angle))
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                WhimCornerLogo(imageBundle: imageBundle)
                    .frame(width: side * 0.53, height: side * 0.19)
                    .position(x: center.x + outward.dx * side * 0.22,
                              y: center.y + outward.dy * side * 0.22)
                Canvas { context, _ in
                    let characters = Array(String(localized: "Record").localizedUppercase)
                    let glyphs = characters.map { character in
                        context.resolve(Text(String(character))
                            .font(.system(size: side * 0.225, weight: .medium))
                            .foregroundStyle(.white))
                    }
                    let widths = glyphs.map { $0.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity)).width }
                    let spacing = side * 0.006
                    let width = widths.reduce(0, +) + spacing * CGFloat(max(0, characters.count - 1))
                    let scale = min(1, side * 0.84 / max(width, 1))
                    let radius = side * 3
                    var cursor = -width * scale / 2
                    for (glyph, width) in zip(glyphs, widths) {
                        let advance = width * scale
                        let offset = (cursor + advance / 2) / radius
                        let radial = -side * 0.175 + radius * (cos(offset) - 1)
                        let along = radius * sin(offset)
                        var layer = context
                        layer.translateBy(x: center.x + outward.dx * radial + tangent.dx * along,
                                          y: center.y + outward.dy * radial + tangent.dy * along)
                        layer.rotate(by: .radians(angle + (top ? offset : -offset)))
                        layer.scaleBy(x: scale, y: scale)
                        layer.draw(glyph, at: .zero)
                        cursor += advance + spacing * scale
                    }
                }
                .accessibilityHidden(true)
            }
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

    var body: some View { label.baselineOffset(14) }

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
