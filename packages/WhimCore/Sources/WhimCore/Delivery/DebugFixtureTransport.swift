#if DEBUG
import Foundation

/// Overrides only the dedicated synthetic fixture destination in development builds.
public struct DebugFixtureTransport: HTTPTransport {
    private let loopback: URL
    private let base: any HTTPTransport
    public static func from(arguments: [String], base: any HTTPTransport) throws -> DebugFixtureTransport? {
        guard let index = arguments.firstIndex(of: "-WhimFixtureWebhookURL") else { return nil }
        guard arguments.indices.contains(index + 1), let url = URL(string: arguments[index + 1]),
              url.scheme == "http", url.host == "127.0.0.1", let port = url.port,
              (1...65535).contains(port), url.user == nil, url.password == nil,
              url.fragment == nil, url.query == nil, url.path == "/receive" else {
            throw WhimServiceError.setupRequired("The development webhook fixture must be loopback.")
        }
        return .init(loopback: url, base: base)
    }
    public func send(_ request: WebhookRequest) async throws -> HTTPResponse {
        guard request.url.scheme == "https", request.url.host == "whim-fixture.invalid",
              request.url.path == "/receive", request.url.user == nil, request.url.password == nil,
              request.url.port == nil, request.url.query == nil, request.url.fragment == nil else {
            return try await base.send(request)
        }
        return try await base.send(.init(url: loopback, method: request.method,
            headers: request.headers, bodyFileURL: request.bodyFileURL, contentLength: request.contentLength))
    }
    static var offline: Bool { ProcessInfo.processInfo.arguments.contains("-WhimFixtureOffline") }
}
#endif
