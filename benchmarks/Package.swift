// swift-tools-version: 6.0
import PackageDescription

let package = Package(name: "WhimBenchmarkSupport", platforms: [.macOS(.v15), .iOS(.v18)], targets: [
    .target(name: "WhimBenchmarkSupport", path: "support", exclude: ["BenchmarkMetrics.test.swift", "comparison-cases.json"], sources: ["BenchmarkMetrics.swift"]),
    .testTarget(name: "WhimBenchmarkSupportTests", dependencies: ["WhimBenchmarkSupport"], path: "support", exclude: ["BenchmarkMetrics.swift"], sources: ["BenchmarkMetrics.test.swift"], resources: [.copy("comparison-cases.json")]),
])
