import SwiftUI
import WhimCore
import WhimIPhone
struct TimelineView: View {
    var model: IPhoneModel
    var open: (NoteID) -> Void
    @State private var filter = "All"
    private var visible: [NoteProjection] {
        model.notes.filter { note in filter == "All" || (filter == "Queued" ? [.queued, .setupRequired, .sending].contains(note.status) : note.status.rawValue == filter.lowercased()) }
    }
    var body: some View {
        WhimContent {
            Text("Your Whims").whimTitle()
            ViewThatFits(in: .horizontal) { HStack { filters }; VStack(alignment: .leading) { filters } }
            if filter == "Failed" && visible.contains(where: { !$0.requiresReview }) {
                Button("Retry all failed Notes") { Task { await model.perform { _ = try await model.client.retryAllFailed() } } }
            }
            if visible.isEmpty { Text("No Notes here yet. Capture a thought.").foregroundStyle(.secondary) }
            ForEach(visible, id: \.id) { note in
                NoteRowView(note: note, open: { open(note.id) }, retry: { Task { await model.perform { try await model.client.retry(noteID: note.id) } } })
            }
        }.accessibilityIdentifier("whim-home").overlay(alignment: .bottom) {
            Button { Task { await model.startRecording() } } label: {
                Text("● Record").font(.title3.weight(.semibold)).foregroundStyle(.white).padding(20).background(Color.whimAccent).clipShape(Capsule())
            }.buttonStyle(.plain).accessibilityLabel("Record a Whim").accessibilityIdentifier("record-button").padding(.bottom, 24).disabled(model.isRecordingPending)
        }
    }
    private var filters: some View {
        ForEach(["All", "Queued", "Failed", "Sent"], id: \.self) { value in
            Button(value) { filter = value }.accessibilityLabel("\(value) filter").accessibilityAddTraits(filter == value ? .isSelected : [])
        }
    }
}
