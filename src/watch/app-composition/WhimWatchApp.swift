import SwiftUI
import WhimCore
import WatchKit

@main
struct WhimWatchApp: App {
    @WKApplicationDelegateAdaptor(WhimWatchDelegate.self) private var delegate
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
                do { model = WatchModel(client: try await WhimWatchRuntime.service()) }
                catch { self.error = String(describing: error) }
            }
        }
    }
}

final class WhimWatchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let connectivity = task as? WKWatchConnectivityRefreshBackgroundTask {
                WatchBackgroundTaskCoordinator.shared.retain(connectivity)
                Task { _ = try? await WhimWatchRuntime.service() }
            } else { task.setTaskCompletedWithSnapshot(false) }
        }
    }
}

@MainActor
private enum WhimWatchRuntime {
    private static var instance: Task<WhimService, Error>?
    static func service() async throws -> WhimService {
        if let instance { return try await instance.value }
        let task = Task { try await WhimProductionComposition.make() }
        instance = task
        do { return try await task.value }
        catch { instance = nil; throw error }
    }
}
