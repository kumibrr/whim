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
    case url(Int)
    case network
    case invalidResponse

    public var description: String {
        switch self {
        case .url(let code):
            switch code {
            case URLError.cannotFindHost.rawValue, URLError.dnsLookupFailed.rawValue:
                "DNS lookup failed: the webhook hostname could not be found. Check the URL and the server’s DNS configuration."
            case URLError.cannotConnectToHost.rawValue:
                "Could not connect to the webhook. Check that the server is listening and reachable."
            case URLError.timedOut.rawValue:
                "The webhook request timed out. Check server availability and try again."
            case URLError.notConnectedToInternet.rawValue:
                "No internet connection. Reconnect and test the webhook again."
            case -1206 ... -1200:
                "TLS certificate validation failed. Check the server’s HTTPS certificate and certificate chain."
            default:
                "Network request failed (URL error \(code)). Check connectivity and the webhook URL."
            }
        case .network: "The webhook could not be reached."
        case .invalidResponse: "The webhook returned an invalid response."
        }
    }
}
