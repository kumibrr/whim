import SwiftUI
import WhimCore

struct WatchRootView: View {
    @Bindable var model: WatchModel
    @Environment(\.scenePhase) private var scenePhase

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
                            if let error = model.error {
                                Text(error).foregroundStyle(.red)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 20)
                        .frame(minHeight: geometry.size.height, alignment: .top)
                        .id("previous-notes")
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollBounceBehavior(.always)
                .background(Color.black)
            }
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .task { await model.activate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.activate() } }
        }
    }
}
