import SwiftUI
import WhimCore
import WatchKit

@main
struct WhimWatchApp: App {
    @WKApplicationDelegateAdaptor(WhimWatchDelegate.self) private var delegate
    @State private var model: WatchModel?
    @State private var error: ActionableFailure?
    @State private var starting = false
    var body: some Scene {
        WindowGroup {
            Group {
                if let model { WatchRootView(model: model) }
                else { WatchStartupShell(failure: error, busy: starting) { Task { await launch() } } }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("watch-root")
            .task { await launch() }
        }
    }
    @MainActor private func launch() async {
        guard model == nil, !starting else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #endif
        starting = true
        defer { starting = false }
        do { model = WatchModel(client: try await WhimWatchRuntime.service()); error = nil }
        catch { self.error = ActionableFailure(error, operation: .preparation) }
    }
}

final class WhimWatchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let connectivity = task as? WKWatchConnectivityRefreshBackgroundTask {
                WatchBackgroundTaskCoordinator.shared.retain(connectivity)
                Task {
                    let coordinator = WatchBackgroundTaskCoordinator.shared
                    coordinator.beginProcessing()
                    defer { coordinator.endProcessing() }
                    if let service = try? await WhimWatchRuntime.service() { try? await service.launch() }
                }
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
