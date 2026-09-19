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
            Text("Previous notes").font(.system(size: 28, weight: .semibold)).accessibilityAddTraits(.isHeader)
            if let error = model.error { WhimErrorText(message: error.message) }
            ViewThatFits(in: .horizontal) { HStack { filters }; VStack(alignment: .leading) { filters } }
            if filter == "Failed" && visible.contains(where: { !$0.requiresReview }) {
                Button("Retry all failed Notes") { Task { await model.perform { _ = try await model.client.retryAllFailed() } } }
            }
            if visible.isEmpty { Text("No Notes here yet. Capture a thought.").foregroundStyle(.secondary) }
            LazyVStack(spacing: 14) {
                ForEach(visible, id: \.id) { note in
                    NoteRowView(note: note, waveform: model.waveforms[note.id], playback: model.playback,
                        open: { open(note.id) },
                        retry: { Task { await model.perform { try await model.client.retry(noteID: note.id) } } },
                        togglePlayback: {
                            Task {
                                if model.playback?.noteID == note.id.rawValue.uuidString.lowercased(), model.playback?.isPlaying == true {
                                    await model.stopInlinePlayback()
                                } else { await model.playInline(note.id) }
                            }
                        })
                        .task(id: note.hasLocalAudio) { await model.loadWaveform(note.id) }
                }
            }
        }.accessibilityIdentifier("notes-list")
    }
    private var filters: some View {
        ForEach(["All", "Queued", "Failed", "Sent"], id: \.self) { value in
            Button { filter = value } label: {
                Text(value).font(.system(.caption, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 9)
                    .foregroundStyle(filter == value ? .black : .white.opacity(0.65))
                    .background(filter == value ? Color.white : Color.white.opacity(0.06), in: Capsule())
                    .frame(minHeight: 48)
            }.buttonStyle(.plain).accessibilityLabel("\(value) filter").accessibilityAddTraits(filter == value ? .isSelected : [])
        }
    }
}

/// The handle owns dismissal; the list keeps its own scrolling gesture.
struct HistorySheet<Content: View>: View {
    var model: IPhoneModel
    var openingTranslation: Double
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var translation = 0.0
    private var animation: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.9) }
    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height * 0.9
            let isOpen = model.isHistoryPresented
            let reveal = isOpen ? height - max(0, translation) : max(0, -openingTranslation)
            ZStack(alignment: .bottom) {
                if isOpen || reveal > 0 {
                    Color.black.opacity(0.5 * min(1, reveal / height)).ignoresSafeArea()
                        .onTapGesture { close() }.accessibilityHidden(true)
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: 44)
                            Capsule().fill(.white.opacity(0.3)).frame(width: 32, height: 4)
                                .frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
                                .gesture(DragGesture().updating($translation) { value, state, _ in
                                    state = max(0, value.translation.height)
                                }.onEnded { value in
                                    if value.translation.height > 100 || value.predictedEndTranslation.height > height * 0.3 { close() }
                                }).accessibilityHidden(true)
                            Button(action: close) {
                                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel("Close history").accessibilityIdentifier("history-close")
                        }.padding(.horizontal, 8).frame(height: 44)
                        content
                    }.frame(height: height)
                        .background(Color(white: 0.035), in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
                        .overlay(alignment: .top) {
                            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                                .stroke(.white.opacity(0.13), lineWidth: 0.5).allowsHitTesting(false)
                        }
                        .offset(y: max(0, height - reveal))
                        .accessibilityElement(children: .contain).accessibilityIdentifier("history-sheet")
                        .accessibilityAction(.escape) { close() }
                }
            }.animation(animation, value: model.isHistoryPresented)
                .animation(animation, value: translation == 0)
                .onChange(of: model.isHistoryPresented) { old, new in
                    if !old && new { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
                }
        }
    }
    private func close() { Task { await model.closeHistory() } }
}
