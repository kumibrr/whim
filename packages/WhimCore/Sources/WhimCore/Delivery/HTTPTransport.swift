import Foundation

public struct HTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: WebhookRequest) async throws -> HTTPResponse
}

public enum HTTPTransportError: Error, Equatable, CustomStringConvertible {
    case network
    case invalidResponse

    public var description: String {
        switch self {
        case .network: "The webhook could not be reached."
        case .invalidResponse: "The webhook returned an invalid response."
        }
    }
}
