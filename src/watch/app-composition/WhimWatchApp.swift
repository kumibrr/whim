import SwiftUI
import WhimCore

@main
struct WhimWatchApp: App {
    @State private var model: WatchModel?
    @State private var error: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let model { WatchRootView(model: model) }
                else if let error { Text(error) }
                else { ProgressView("Opening Whim") }
            }
            .accessibilityIdentifier("watch-root")
            .task {
                guard model == nil else { return }
                #if DEBUG
                if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
                #endif
                do { model = WatchModel(client: try await WhimProductionComposition.make()) }
                catch { self.error = String(describing: error) }
            }
        }
    }
}
