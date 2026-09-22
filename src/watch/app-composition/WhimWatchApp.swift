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
        do { model = WatchModel(client: try await WhimRuntime.shared.service()); error = nil }
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
                    if let service = try? await WhimRuntime.shared.service() { try? await service.launch() }
                }
            } else if let refresh = task as? WKApplicationRefreshBackgroundTask,
                      WatchBackgroundScheduler.shared.accepts(refresh.userInfo) {
                let worker = Task {
                    defer { refresh.setTaskCompletedWithSnapshot(false) }
                    do {
                        let service = try await WhimRuntime.shared.service()
                        try Task.checkCancellation()
                        try await service.performBackgroundMaintenance()
                    } catch { }
                }
                refresh.expirationHandler = { worker.cancel() }
            } else { task.setTaskCompletedWithSnapshot(false) }
        }
    }
}
