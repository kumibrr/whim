import Foundation
import XCTest
import Darwin

@MainActor
final class WhimPerformanceTests: XCTestCase {
    private var measurements: [String: [String: [[Double]]]] = [:]
    private let emptyID = UUID().uuidString
    private let populatedID = UUID().uuidString
    private var raw: [String: Any] = [:]
    private var input: [String: Any] = [:]
    private var policy = BenchmarkMetrics.Policy()
    private var baseline: [String: Any]?
    private var completed = false

    override func tearDown() async throws {
        try attachObservation()
        try await super.tearDown()
    }

    private func attachObservation() throws {
        // XCTest invokes teardown even when an accessibility lookup raises an
        // Objective-C exception, which does not unwind Swift defer reliably.
        if !raw.isEmpty {
            raw["metrics"] = measurements
            if !completed { raw["failure"] = ["code": "measurementFailed"] }
            let data = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "whim-benchmark-observation.json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCUIApplication(bundleIdentifier: "app.whim.ios").terminate()
    }

    func testBenchmarkOperations() throws {
        // XCTest's stop-on-first-failure raises an Objective-C exception, which
        // can bypass Swift defer and lose the very samples needed on failures.
        continueAfterFailure = true
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "BenchmarkInput", withExtension: "json"))
        input = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        policy = try JSONDecoder().decode(BenchmarkMetrics.Policy.self, from: JSONSerialization.data(withJSONObject: input["policy"]!))
        var environment = try XCTUnwrap(input["environment"] as? [String: String])
        let variables = ProcessInfo.processInfo.environment
        #if arch(arm64)
        environment["architecture"] = "arm64"
        #else
        environment["architecture"] = "x86_64"
        #endif
        environment["cpu"] = hostValue("machdep.cpu.brand_string")
        environment["kernel"] = hostValue("kern.osrelease")
        environment["runtime"] = ProcessInfo.processInfo.operatingSystemVersionString
        environment["device"] = try XCTUnwrap(variables["CI_TEST_DESTINATION_DEVICE_TYPE"] ?? variables["SIMULATOR_MODEL_IDENTIFIER"])
        let frozen = try XCTUnwrap(input["frozen"] as? [String: Any])
        let candidates = frozen["candidates"] as? [[String: Any]] ?? []
        let candidate = candidates.first { ($0["record"] as? [String: Any])?["environment"] as? [String: String] == environment }
        baseline = candidate?["record"] as? [String: Any]
        let snapshot: [String: Any] = ["historySHA": frozen["historySHA"]!, "policyHash": frozen["policyHash"]!,
            "baselinePath": candidate?["path"] ?? NSNull(), "baselineHash": candidate?["hash"] ?? NSNull()]
        var run = try XCTUnwrap(input["run"] as? [String: Any])
        run["measuredAt"] = ISO8601DateFormatter().string(from: Date())
        raw = ["schemaVersion": 1, "protocol": input["protocol"]!, "fixture": input["fixture"]!,
            "source": input["source"]!, "run": run, "environment": environment, "snapshot": snapshot]
        guard !environment.values.contains(where: { $0 == "pending" || $0 == "unavailable" }) else {
            throw BenchmarkMetrics.InvalidMeasurement.samples
        }
        try setupFixture(id: emptyID, count: 0)
        try setupFixture(id: populatedID, count: 1000)
        var outcomes: [String] = []
        for metric in ["launch.empty", "launch.populated", "record.populated", "stop.populated", "timeline.populated"] {
            for _ in 0..<policy.warmups { _ = try iteration(metric) }
            measurements[metric] = ["batches": [[]]]
            for _ in 0..<policy.samples { measurements[metric]!["batches"]![0].append(try iteration(metric)) }
            var decision = try BenchmarkMetrics.evaluate(measurements[metric]!["batches"]!, baseline: baselineMedian(metric), policy: policy)
            if decision.outcome == "confirmationRequired" {
                measurements[metric]!["batches"]!.append([])
                for _ in 0..<policy.samples { measurements[metric]!["batches"]![1].append(try iteration(metric)) }
                decision = try BenchmarkMetrics.evaluate(measurements[metric]!["batches"]!, baseline: baselineMedian(metric), policy: policy)
            }
            outcomes.append(decision.outcome)
        }
        // Attach the complete observations even when the performance assertion
        // fails. The trusted collector independently checks this frozen decision.
        completed = true
        let source = try XCTUnwrap(input["source"] as? [String: Any])
        if (source["context"] as? String)?.hasPrefix("pr/") == true {
            XCTAssertNotNil(baseline, "No compatible main baseline; retain this provisional observation and rerun after seeding main")
        }
        XCTAssertFalse(outcomes.contains("regression"), "Confirmed performance regression; see benchmark observation attachment")
        XCTAssertFalse(outcomes.contains("inconclusive"), "Unstable benchmark measurements; rerun without advancing the baseline")
    }

    private func baselineMedian(_ metric: String) throws -> Double? {
        guard let baseline else { return nil }
        let metrics = try XCTUnwrap(baseline["metrics"] as? [String: [String: [[Double]]]])
        return try BenchmarkMetrics.summarize(XCTUnwrap(metrics[metric]?["batches"]?.first), policy: policy).median
    }

    private func application(id: String, count: Int, setup: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "app.whim.ios")
        app.launchArguments = ["-WhimBenchmarkID", id, "-WhimBenchmarkNotes", String(count), "-WhimFixtureOffline"]
        if setup { app.launchArguments.append("-WhimBenchmarkSetup") }
        return app
    }

    private func setupFixture(id: String, count: Int) throws {
        let app = application(id: id, count: count, setup: true)
        app.launch()
        // Complete the normal release announcement only in untimed setup. The
        // acknowledgement persists in this fixture's isolated preference suite.
        if app.otherElements["app-update-sheet"].waitForExistence(timeout: 10) {
            try ready(app.buttons["app-update-continue"])
            app.buttons["app-update-continue"].tap()
        }
        try ready(app.buttons["record-button"], timeout: 120)
        try ready(app.buttons["history-hint"])
        app.buttons["history-hint"].tap()
        if count > 0 { try expectedSeed(app) }
        else { try ready(app.staticTexts["No Notes here yet. Capture a thought."], interactive: false) }
        app.terminate()
    }

    private func iteration(_ metric: String) throws -> Double {
        let empty = metric == "launch.empty"
        let app = application(id: empty ? emptyID : populatedID, count: empty ? 0 : 1000)
        app.terminate()
        if metric.hasPrefix("launch.") {
            let start = ProcessInfo.processInfo.systemUptime
            app.launch()
            try ready(app.buttons["record-button"])
            let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
            app.terminate()
            return ms
        }
        app.launch()
        try ready(app.buttons["record-button"])
        if metric == "timeline.populated" {
            try ready(app.buttons["history-hint"])
            let start = ProcessInfo.processInfo.systemUptime
            app.buttons["history-hint"].tap()
            try expectedSeed(app)
            let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
            app.terminate()
            return ms
        }
        if metric == "record.populated" {
            let start = ProcessInfo.processInfo.systemUptime
            app.buttons["record-button"].tap()
            try ready(app.buttons["stop-recording"])
            let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
            app.buttons["discard-recording"].tap()
            try ready(app.buttons["record-button"])
            app.terminate()
            return ms
        }
        app.buttons["record-button"].tap()
        try ready(app.buttons["stop-recording"])
        guard !app.staticTexts["Note saved"].exists else {
            XCTFail("A previous session's feedback cannot complete this measurement")
            throw BenchmarkMetrics.InvalidMeasurement.samples
        }
        let start = ProcessInfo.processInfo.systemUptime
        app.buttons["stop-recording"].tap()
        try ready(app.staticTexts["Note saved"], interactive: false)
        try ready(app.buttons["record-button"])
        let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
        // Save verification and cleanup are outside the Stop interval. A fresh
        // process per sample prevents stale feedback and preserves 1,000 Notes.
        app.buttons["history-hint"].tap()
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "note-row-")).firstMatch
        try ready(first)
        guard !first.label.contains("Benchmark Note") else {
            XCTFail("Stop must durably save a new Note")
            throw BenchmarkMetrics.InvalidMeasurement.samples
        }
        first.tap()
        try ready(app.buttons["note-delete"])
        app.buttons["note-delete"].tap()
        try ready(app.buttons["Confirm delete"])
        app.buttons["Confirm delete"].tap()
        try expectedSeed(app)
        app.terminate()
        return ms
    }

    private func expectedSeed(_ app: XCUIApplication) throws {
        try ready(app.otherElements["history-sheet"], interactive: false)
        let newest = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Benchmark Note 0999")).firstMatch
        try ready(newest)
    }

    private func ready(_ element: XCUIElement, timeout: TimeInterval = 30, interactive: Bool = true) throws {
        // Do not resolve elementType/identifier before existence: XCTest raises
        // an exception for a transiently absent element instead of waiting.
        let predicate = NSPredicate(format: interactive
            ? "exists == true AND enabled == true AND hittable == true"
            : "exists == true AND enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            XCTFail("Required benchmark observation was unavailable")
            throw BenchmarkMetrics.InvalidMeasurement.samples
        }
    }

    private func hostValue(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unavailable" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "unavailable" }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
