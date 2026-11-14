import Foundation
import XCTest
@testable import WhimBenchmarkSupport

final class BenchmarkMetricsTests: XCTestCase {
    func testNativeDecisionsMatchSharedConformanceCases() throws {
        struct Case: Decodable { let name: String; let baseline: Double?; let values: [[Double]]; let expected: String }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "comparison-cases", withExtension: "json"))
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
        for c in cases {
            let batches = c.values.map { $0.count == 1 ? Array(repeating: $0[0], count: 10) : $0 }
            XCTAssertEqual(try BenchmarkMetrics.evaluate(batches, baseline: c.baseline, policy: .init()).outcome, c.expected, c.name)
        }
    }

    func testIncompleteAndNonfiniteMeasurementsCannotPass() throws {
        for values in [[Double](), Array(repeating: 1.0, count: 9), Array(repeating: -.infinity, count: 10), Array(repeating: -1.0, count: 10)] {
            XCTAssertThrowsError(try BenchmarkMetrics.evaluate([values], baseline: nil, policy: .init()))
        }
        XCTAssertThrowsError(try BenchmarkMetrics.evaluate([], baseline: nil, policy: .init()))
    }
}
