import Foundation

public protocol ConnectivityBackgroundTask: AnyObject, Sendable { func complete() }

public final class WatchBackgroundTaskCoordinator: @unchecked Sendable {
    public static let shared = WatchBackgroundTaskCoordinator()
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: any ConnectivityBackgroundTask] = [:]
    private var completed: [ObjectIdentifier: WeakTask] = [:]
    private var activated = false
    private var pending = true
    private var processing = 0
    public init() {}

    public func retain(_ task: any ConnectivityBackgroundTask) {
        let ready = lock.withLock { () -> [any ConnectivityBackgroundTask] in
            completed = completed.filter { $0.value.value != nil }
            let id = ObjectIdentifier(task)
            guard completed[id] == nil else { return [] }
            tasks[id] = task
            return drain()
        }
        ready.forEach { $0.complete() }
    }
    public func update(activated: Bool, hasContentPending: Bool) {
        let ready = lock.withLock {
            self.activated = activated; pending = hasContentPending
            return drain()
        }
        ready.forEach { $0.complete() }
    }
    public func beginProcessing() { lock.withLock { processing += 1 } }
    public func endProcessing() {
        let ready = lock.withLock { processing = max(0, processing - 1); return drain() }
        ready.forEach { $0.complete() }
    }
    private func drain() -> [any ConnectivityBackgroundTask] {
        guard activated, !pending, processing == 0 else { return [] }
        let ready = Array(tasks.values)
        for task in ready { completed[ObjectIdentifier(task)] = WeakTask(task) }
        tasks.removeAll()
        return ready
    }
}

private final class WeakTask {
    weak var value: (any ConnectivityBackgroundTask)?
    init(_ value: any ConnectivityBackgroundTask) { self.value = value }
}

#if os(watchOS)
import WatchKit
extension WKWatchConnectivityRefreshBackgroundTask: @retroactive @unchecked Sendable {}
extension WKWatchConnectivityRefreshBackgroundTask: ConnectivityBackgroundTask {
    public func complete() { setTaskCompletedWithSnapshot(false) }
}
#endif
