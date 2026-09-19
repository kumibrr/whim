import SwiftUI
import WhimCore
import WhimIPhone

struct NoteRowView: View {
    let note: NoteProjection
    let waveform: AudioWaveform?
    let playback: PlaybackProjection?
    let open: () -> Void
    let retry: () -> Void
    let togglePlayback: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var status: String { note.requiresReview ? "⚠ Review required" : TimelineFormat.status(note.status) }
    private var audio: String? { note.hasLocalAudio ? nil : note.localError == nil ? "Audio expired" : "Audio unavailable" }
    private var id: String { note.id.rawValue.uuidString.lowercased() }
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
                Text("\(TimelineFormat.source(note.source)) · \(TimelineFormat.duration(seconds: note.duration))")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(status).fontWeight(note.status == .failed || note.requiresReview ? .semibold : .regular)
            }.font(.caption2)
            if let audio { Text(audio).font(.caption).foregroundStyle(.secondary) }
            if note.workflowError != nil { Label("Delivery needs attention", systemImage: "exclamationmark.circle").font(.caption) }
            if note.status == .failed && !note.requiresReview {
                Button("Retry", action: retry).accessibilityLabel("Retry \(note.title)")
                    .font(.footnote).frame(minHeight: 48)
            }
        }.padding(18).whimGlass(in: RoundedRectangle(cornerRadius: 24))
            .accessibilityElement(children: .contain)
    }
    private var metadata: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 7) {
                Text(note.title).font(.system(.subheadline, weight: .semibold)).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(["Open \(note.title)", TimelineFormat.date(note.createdAt), TimelineFormat.source(note.source), TimelineFormat.duration(seconds: note.duration), status, audio, note.workflowError == nil ? nil : "Delivery needs attention"].compactMap { $0 }.joined(separator: ", "))
            .accessibilityIdentifier("note-row-\(id)")
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
            .accessibilityValue(isPlaying ? "\(TimelineFormat.duration(seconds: playback?.elapsedSeconds ?? 0)) of \(TimelineFormat.duration(seconds: note.duration))" : "")
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
