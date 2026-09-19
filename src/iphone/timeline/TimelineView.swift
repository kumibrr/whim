import SwiftUI
import WhimCore
import WhimIPhone
struct TimelineView: View {
    var model: IPhoneModel
    @Binding var sheetDragTranslation: Double
    var dismiss: () -> Void
    var open: (NoteID) -> Void
    @State private var filter = "All"
    @State private var isAtTop = true
    @State private var dragBeganAtTop: Bool?
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
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y <= geometry.contentInsets.top + 1
        } action: { _, newValue in
            isAtTop = newValue
        }
        .scrollDisabled(sheetDragTranslation > 0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragBeganAtTop == nil { dragBeganAtTop = isAtTop }
                    sheetDragTranslation = HistoryScrollDismissal.dragOffset(
                        gestureBeganAtTop: dragBeganAtTop ?? isAtTop,
                        translation: value.translation.height
                    )
                }
                .onEnded { value in
                    let beganAtTop = dragBeganAtTop ?? isAtTop
                    dragBeganAtTop = nil
                    if HistoryScrollDismissal.shouldDismiss(
                        gestureBeganAtTop: beganAtTop,
                        translation: value.translation.height,
                        predictedTranslation: value.predictedEndTranslation.height
                    ) {
                        dismiss()
                    } else {
                        sheetDragTranslation = 0
                    }
                }
        )
        .accessibilityIdentifier("notes-list")
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

/// The handle and a fresh downward list drag from the top own dismissal.
struct HistorySheet<Content: View>: View {
    var model: IPhoneModel
    var openingTranslation: Double
    @ViewBuilder var content: (Binding<Double>) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var translation = 0.0
    @State private var contentTranslation = 0.0
    private var animation: Animation? {
        reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0.15)
    }
    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height * 0.9
            let isOpen = model.isHistoryPresented
            let closingTranslation = max(translation, contentTranslation)
            let reveal = isOpen
                ? max(0, height - closingTranslation)
                : HistorySheetMotion.openingReveal(translation: openingTranslation, height: height)
            let offset = HistorySheetMotion.offset(
                isOpen: isOpen,
                openingTranslation: openingTranslation,
                closingTranslation: closingTranslation,
                height: height,
                safeAreaBottom: geometry.safeAreaInsets.bottom
            )
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.5 * min(1, reveal / height)).ignoresSafeArea()
                    .onTapGesture { close() }.accessibilityHidden(true)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 48)
                        Capsule().fill(.white.opacity(0.3)).frame(width: 32, height: 4)
                            .frame(maxWidth: .infinity).frame(height: 52).contentShape(Rectangle())
                            .gesture(DragGesture().updating($translation) { value, state, _ in
                                state = max(0, value.translation.height)
                            }.onEnded { value in
                                if value.translation.height > 100 || value.predictedEndTranslation.height > height * 0.3 { close() }
                            }).accessibilityHidden(true)
                        closeButton.buttonBorderShape(.circle)
                            .frame(width: 48, height: 48)
                            .accessibilityLabel("Close history").accessibilityIdentifier("history-close")
                    }.padding(.horizontal, 8).frame(height: 52)
                    content($contentTranslation)
                }.frame(height: height)
                    .background(Color(uiColor: .systemBackground), in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
                    .overlay(alignment: .top) {
                        UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                            .stroke(.white.opacity(0.13), lineWidth: 0.5).allowsHitTesting(false)
                    }
                    .offset(y: offset)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(isOpen ? "history-sheet" : "history-sheet-hidden")
                    .accessibilityAction(.escape) { close() }
            }.animation(animation, value: model.isHistoryPresented)
                .animation(animation, value: translation == 0)
                .animation(animation, value: contentTranslation == 0)
                .allowsHitTesting(isOpen || reveal > 0)
                .accessibilityHidden(!isOpen)
                .onChange(of: model.isHistoryPresented) { old, new in
                    if !old && new { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
                    if old && !new { contentTranslation = 0 }
                }
        }
    }
    @ViewBuilder private var closeButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: close) {
                Label("Close history", systemImage: "xmark").labelStyle(.iconOnly)
            }.buttonStyle(.glass).controlSize(.large)
        } else {
            Button(action: close) {
                Label("Close history", systemImage: "xmark").labelStyle(.iconOnly)
            }.buttonStyle(.bordered).controlSize(.large)
        }
    }
    private func close() { Task { await model.closeHistory() } }
}
