import Foundation

/// Shared by the native test bundle and its fast, dependency-free companion suite.
/// This module is never linked into the distributed app.
public enum BenchmarkMetrics {
    public struct Policy: Codable, Sendable {
        public var samples = 10
        public var warmups = 2
        public var relativeTolerance = 0.2
        public var absoluteToleranceMS = 100.0
        public var maxMADFraction = 0.15
        public init() {}
    }
    public struct Summary: Codable, Sendable {
        public let count: Int
        public let median: Double
        public let min: Double
        public let max: Double
        public let mad: Double
    }
    public struct Decision: Codable, Sendable {
        public let outcome: String
        public let summaries: [Summary]
    }
    public enum InvalidMeasurement: Error { case samples, policy, baseline }

    public static func summarize(_ values: [Double], policy: Policy) throws -> Summary {
        guard (3...100).contains(policy.samples), (0...10).contains(policy.warmups),
              [policy.relativeTolerance, policy.absoluteToleranceMS, policy.maxMADFraction].allSatisfy({ $0.isFinite && $0 >= 0 }),
              policy.relativeTolerance <= 1, policy.maxMADFraction <= 1 else { throw InvalidMeasurement.policy }
        guard values.count == policy.samples, values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 3_600_000 }) else { throw InvalidMeasurement.samples }
        let sorted = values.sorted()
        let center = median(sorted)
        return Summary(count: values.count, median: center, min: sorted[0], max: sorted[sorted.count - 1],
                       mad: median(values.map { abs($0 - center) }.sorted()))
    }

    public static func evaluate(_ batches: [[Double]], baseline: Double?, policy: Policy) throws -> Decision {
        guard (1...2).contains(batches.count) else { throw InvalidMeasurement.samples }
        if let baseline, !baseline.isFinite || baseline <= 0 { throw InvalidMeasurement.baseline }
        let summaries = try batches.map { try summarize($0, policy: policy) }
        let outcome: String
        if summaries.contains(where: { $0.median <= 0 || $0.mad > $0.median * policy.maxMADFraction }) { outcome = "inconclusive" }
        else if let baseline {
            func slower(_ value: Summary) -> Bool {
                value.median - baseline > policy.absoluteToleranceMS && value.median > baseline * (1 + policy.relativeTolerance)
            }
            if !slower(summaries[0]) { outcome = "pass" }
            else if summaries.count == 1 { outcome = "confirmationRequired" }
            else { outcome = slower(summaries[1]) ? "regression" : "inconclusive" }
        } else { outcome = "baseline" }
        return Decision(outcome: outcome, summaries: summaries)
    }

    private static func median(_ sorted: [Double]) -> Double {
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}
