import SwiftUI
import WhimCore

struct WatchRootView: View {
    @Bindable var model: WatchModel
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    if model.recording != nil { WatchRecorderView(model: model) }
                    else if model.permission == .granted {
                        Text("Ready to record")
                        Button("Record") { Task { await model.record() } }
                            .accessibilityIdentifier("watch-record")
                    } else {
                        Text("Microphone access is required to capture a Note.")
                        if model.permission == .notDetermined {
                            Button("Allow microphone") { Task { await model.requestPermission() } }
                        } else {
                            Text("On Apple Watch, open Settings > Privacy & Security > Microphone and allow Whim.")
                        }
                    }
                    Button("Recent Notes") { model.showsRecent = true }
                        .accessibilityIdentifier("watch-recent-notes")
                    WebhookStatusView(available: model.configurationAvailable, synchronization: model.synchronization)
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Whim")
            .navigationDestination(isPresented: $model.showsRecent) { WatchRecentNotesView(model: model) }
        }
        .tint(Color(red: 1, green: 0.40, blue: 0.32))
        .task { await model.activate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.activate() } }
        }
    }
}
