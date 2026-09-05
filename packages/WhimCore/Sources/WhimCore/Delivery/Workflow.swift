public struct StepDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let needs: [String]

    public init(id: String, needs: [String]) {
        self.id = id
        self.needs = needs
    }
}

public struct WorkflowDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let steps: [StepDefinition]

    public init(id: String, steps: [StepDefinition]) {
        self.id = id
        self.steps = steps
    }

    public static let `default` = WorkflowDefinition(
        id: "default",
        steps: [
            StepDefinition(id: "title_enrichment", needs: []),
            StepDefinition(id: "webhook_delivery", needs: []),
        ]
    )
}
