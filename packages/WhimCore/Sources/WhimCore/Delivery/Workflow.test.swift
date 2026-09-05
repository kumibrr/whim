import XCTest
@testable import WhimCore

final class WorkflowTests: XCTestCase {
    func testDefaultWorkflowHasTwoIndependentStableSteps() {
        let workflow = WorkflowDefinition.default

        XCTAssertEqual(workflow.id, "default")
        XCTAssertEqual(workflow.steps.map(\.id), ["title_enrichment", "webhook_delivery"])
        XCTAssertTrue(workflow.steps.allSatisfy(\.needs.isEmpty))
    }
}
