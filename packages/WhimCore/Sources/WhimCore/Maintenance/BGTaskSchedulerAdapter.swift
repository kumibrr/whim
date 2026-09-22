import Foundation
#if os(iOS)
@preconcurrency import BackgroundTasks

public struct BGTaskSchedulerAdapter: BackgroundScheduling {
    public static let identifier = "app.whim.maintenance"
    public init() {}

    public func replace(with work: BackgroundWork?) async throws {
        guard let work else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
            return
        }
        let request = BGProcessingTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = work.earliest
        request.requiresNetworkConnectivity = work.requiresNetwork
        do { try BGTaskScheduler.shared.submit(request) }
        catch let error as BGTaskScheduler.Error where error.code == .unavailable {
            // Background App Refresh can be disabled; foreground work remains available.
        }
    }

    @available(iOSApplicationExtension, unavailable)
    @MainActor public static func register() {
        _ = registration
    }

    @available(iOSApplicationExtension, unavailable)
    @MainActor private static let registration: Void = {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let completion = BackgroundTaskCompletion(task)
            let worker = Task {
                do {
                    let service = try await WhimRuntime.shared.service()
                    try Task.checkCancellation()
                    try await service.performBackgroundMaintenance()
                    completion.finish(success: true)
                } catch { completion.finish(success: false) }
            }
            task.expirationHandler = { worker.cancel() }
        }
    }()
}

private final class BackgroundTaskCompletion: @unchecked Sendable {
    private let task: BGTask
    init(_ task: BGTask) { self.task = task }
    func finish(success: Bool) { task.setTaskCompleted(success: success) }
}
#endif
