import Foundation

/// App UI and app-process intents must address the same microphone owner.
public actor WhimRuntime {
    public static let shared = WhimRuntime()
    private let make: @Sendable () async throws -> WhimService
    public init(make: @escaping @Sendable () async throws -> WhimService = { try await WhimProductionComposition.make() }) { self.make = make }
    private var instance: Task<WhimService, Error>?
    public func service() async throws -> WhimService {
        if let instance { return try await instance.value }
        let task = Task { try await make() }
        instance = task
        do { return try await task.value }
        catch { instance = nil; throw error }
    }
}
