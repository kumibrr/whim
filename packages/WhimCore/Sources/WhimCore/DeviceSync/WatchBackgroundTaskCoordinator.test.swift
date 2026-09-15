import XCTest
@testable import WhimCore

final class WatchBackgroundTaskCoordinatorTests: XCTestCase {
    func testTasksWaitForActivationAndDrainedContentAndCompleteExactlyOnce() {
        for activationFirst in [false, true] {
            let coordinator = WatchBackgroundTaskCoordinator()
            let first = BackgroundProbe(); let second = BackgroundProbe()
            coordinator.retain(first)
            if activationFirst { coordinator.update(activated: true, hasContentPending: true) }
            else { coordinator.update(activated: false, hasContentPending: false) }
            coordinator.retain(second)
            XCTAssertEqual(first.completions, 0)
            XCTAssertEqual(second.completions, 0)
            coordinator.update(activated: true, hasContentPending: false)
            coordinator.update(activated: true, hasContentPending: false)
            coordinator.retain(first)
            XCTAssertEqual(first.completions, 1)
            XCTAssertEqual(second.completions, 1)
        }
    }
}

private final class BackgroundProbe: ConnectivityBackgroundTask, @unchecked Sendable {
    var completions = 0
    func complete() { completions += 1 }
}
