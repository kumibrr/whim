import SwiftUI
import WhimCore

struct WatchRootView: View {
    @Bindable var model: WatchModel
    @Environment(\.scenePhase) private var scenePhase
    private var visiblePage: Binding<String?> {
        Binding(get: { model.showsRecent ? "previous-notes" : "capture" },
                set: { model.showsRecent = $0 == "previous-notes" })
    }

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
                .scrollPosition(id: visiblePage)
                .scrollBounceBehavior(.always)
                .background(Color.black)
            }
            .ignoresSafeArea()
            .navigationTitle(model.showsRecent ? "Previous Notes" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(model.showsRecent ? .visible : .hidden,
                for: .navigationBar)
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .task {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-WhimCaptureURL"), arguments.indices.contains(index + 1),
               let url = URL(string: arguments[index + 1]) {
                await model.activate(captureURL: url)
                return
            }
            #endif
            await model.activate()
        }
        .onOpenURL { url in
            guard url.scheme == "whim", url.host == "record" else { return }
            model.showsRecent = false
            Task { await model.handleCaptureURL(url) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.activate() } }
        }
    }
}
