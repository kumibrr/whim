import SwiftUI
import WhimCore

struct WatchRootView: View {
    @Bindable var model: WatchModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var visiblePage: String? = "capture"

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        WatchCaptureView(model: model)
                            .frame(height: geometry.size.height)
                            .id("capture")

                        VStack(spacing: 14) {
                            WatchRecentNotesView(model: model)
                            WebhookStatusView(available: model.configurationAvailable,
                                synchronization: model.synchronization)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 90)
                        .padding(.bottom, 20)
                        .frame(minHeight: geometry.size.height, alignment: .top)
                        .id("previous-notes")
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $visiblePage)
                .scrollBounceBehavior(.always)
                .background(Color.black)
            }
            .ignoresSafeArea()
            .navigationTitle(visiblePage == "previous-notes" ? "Previous Notes" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(visiblePage == "previous-notes" ? .visible : .hidden,
                for: .navigationBar)
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .task { await model.activate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.activate() } }
        }
    }
}
