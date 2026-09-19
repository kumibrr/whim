import SwiftUI
import WhimCore
import WhimIPhone
struct NoteRowView: View {
    let note: NoteProjection
    let open: () -> Void
    let retry: () -> Void
    private var status: String { note.requiresReview ? "⚠ Review required" : TimelineFormat.status(note.status) }
    private var audio: String? { note.hasLocalAudio ? nil : note.localError == nil ? "Audio expired" : "Audio unavailable" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(note.title).whimHeading()
                    Text(TimelineFormat.date(note.createdAt)).foregroundStyle(.secondary)
                    Text("\(TimelineFormat.source(note.source)) · \(TimelineFormat.duration(seconds: note.duration))").foregroundStyle(.secondary)
                    Text(status).foregroundStyle(note.status == .failed ? Color.red : .primary)
                    if let audio { Text(audio).foregroundStyle(.secondary) }
                    if note.workflowError != nil { Text("Delivery needs attention").foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(["Open \(note.title)", TimelineFormat.date(note.createdAt), TimelineFormat.source(note.source), TimelineFormat.duration(seconds: note.duration), status, audio, note.workflowError == nil ? nil : "Delivery needs attention"].compactMap { $0 }.joined(separator: ", "))
                .accessibilityIdentifier("note-row-\(note.id.rawValue.uuidString.lowercased())")
            if note.status == .failed && !note.requiresReview { Button("Retry", action: retry).accessibilityLabel("Retry \(note.title)") }
            Divider()
        }.padding(.vertical, 16)
    }
}
