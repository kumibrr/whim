import SwiftUI
import WhimCore
import WhimIPhone

/// Shared presentation inputs; each screen keeps its own canonical projection.
protocol NoteCardPresentation {
    var cardID: String { get }
    var title: String { get }
    var createdAt: Date { get }
    var cardDuration: TimeInterval { get }
    var source: CaptureSource { get }
    var status: DeliveryStatus { get }
    var requiresReview: Bool { get }
    var hasLocalAudio: Bool { get }
    var localError: LocalAudioError? { get }
    var workflowError: DeliveryWorkflowError? { get }
}

extension NoteProjection: NoteCardPresentation {
    var cardID: String { id.rawValue.uuidString.lowercased() }
    var cardDuration: TimeInterval { duration }
}

extension NoteDetailProjection: NoteCardPresentation {
    var cardID: String { id }
    var cardDuration: TimeInterval { durationSeconds }
}

struct NoteRowView: View {
    let note: any NoteCardPresentation
    let waveform: AudioWaveform?
    let playback: PlaybackProjection?
    var playbackFailure: String? = nil
    let open: (() -> Void)?
    let retry: (() -> Void)?
    let togglePlayback: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var status: String { note.requiresReview ? "⚠ Review required" : TimelineFormat.status(note.status) }
    private var audio: String? { note.hasLocalAudio ? nil : note.localError == nil ? "Audio expired" : "Audio unavailable" }
    private var id: String { note.cardID }
    private var isPlaying: Bool { playback?.noteID == id && playback?.isPlaying == true }
    private var progress: Double {
        guard isPlaying, let playback, playback.durationSeconds > 0 else { return 0 }
        return max(0, min(1, playback.elapsedSeconds / playback.durationSeconds))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if typeSize.isAccessibilitySize {
                metadata
                player
            } else {
                HStack(alignment: .center, spacing: 16) {
                    metadata.frame(maxWidth: .infinity, alignment: .leading)
                    player.frame(width: 112)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(TimelineFormat.source(note.source)) · \(TimelineFormat.duration(seconds: note.cardDuration))")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(status).fontWeight(note.status == .failed || note.requiresReview ? .semibold : .regular)
            }.font(.caption2)
            if let audio { Text(audio).font(.caption).foregroundStyle(.secondary) }
            if let playbackFailure {
                WhimErrorText(message: playbackFailure).font(.caption)
                    .accessibilityIdentifier("note-playback-error-\(id)")
            }
            if note.workflowError != nil { Label("Delivery needs attention", systemImage: "exclamationmark.circle").font(.caption) }
            if note.status == .failed && !note.requiresReview, let retry {
                Button("Retry", action: retry).accessibilityLabel("Retry \(note.title)")
                    .font(.footnote).frame(minHeight: 48)
            }
        }.padding(18).whimGlass(in: RoundedRectangle(cornerRadius: 24))
            .accessibilityElement(children: .contain)
    }
    @ViewBuilder private var metadata: some View {
        if let open {
            Button(action: open) { metadataContent }
                .buttonStyle(.plain)
                .accessibilityLabel(["Open \(note.title)", TimelineFormat.date(note.createdAt), TimelineFormat.source(note.source), TimelineFormat.duration(seconds: note.cardDuration), status, audio, note.workflowError == nil ? nil : "Delivery needs attention"].compactMap { $0 }.joined(separator: ", "))
                .accessibilityIdentifier("note-row-\(id)")
        } else {
            metadataContent.accessibilityElement(children: .combine)
        }
    }
    private var metadataContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(note.title).font(.system(.subheadline, weight: .semibold)).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
    }
    private var player: some View {
        Button(action: togglePlayback) {
            HStack(spacing: 8) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 15, weight: .medium)).frame(width: 20)
                NoteWaveformView(waveform: waveform, progress: progress).frame(height: 32)
            }.frame(minHeight: 48).contentShape(Rectangle()).opacity(note.hasLocalAudio ? 1 : 0.35)
        }.buttonStyle(.plain).disabled(!note.hasLocalAudio)
            .accessibilityLabel("\(isPlaying ? "Stop playback of" : "Play") \(note.title)")
            .accessibilityValue(isPlaying ? "\(TimelineFormat.duration(seconds: playback?.elapsedSeconds ?? 0)) of \(TimelineFormat.duration(seconds: note.cardDuration))" : "")
            .accessibilityIdentifier("note-\(isPlaying ? "stop" : "play")-\(id)")
    }
}

struct NoteWaveformView: View {
    let waveform: AudioWaveform?
    let progress: Double
    var body: some View {
        Canvas { context, size in
            var path = Path()
            if case .samples(let samples) = waveform, !samples.isEmpty {
                let count = min(32, samples.count)
                for index in 0..<count {
                    let from = index * samples.count / count
                    let to = (index + 1) * samples.count / count
                    let sample = samples[from..<to].max() ?? 0
                    let height = max(1.5, CGFloat(sample) * size.height)
                    let x = (CGFloat(index) + 0.5) * size.width / CGFloat(count)
                    path.move(to: CGPoint(x: x, y: (size.height - height) / 2))
                    path.addLine(to: CGPoint(x: x, y: (size.height + height) / 2))
                }
            } else {
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            }
            context.stroke(path, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            context.clip(to: Path(CGRect(x: 0, y: 0, width: size.width * progress, height: size.height)))
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }.accessibilityHidden(true)
    }
}
