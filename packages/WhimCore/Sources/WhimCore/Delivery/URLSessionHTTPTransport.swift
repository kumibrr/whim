import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct BoundedResponseAccumulator: Sendable {
    private(set) var data = Data()
    private(set) var totalBytesReceived = 0
    let limit: Int

    init(limit: Int) { self.limit = max(0, limit) }

    mutating func append(_ incoming: Data) {
        totalBytesReceived += incoming.count
        let remaining = max(0, limit - data.count)
        if remaining > 0 { data.append(contentsOf: incoming.prefix(remaining)) }
    }
}

public struct URLSessionHTTPTransport: HTTPTransport {
    public init() {}

    public func send(_ request: WebhookRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: DeliveryTimeouts.request)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = DeliveryTimeouts.request
        configuration.timeoutIntervalForResource = DeliveryTimeouts.resource
        configuration.httpShouldSetCookies = false
        do {
            return try await BoundedUploadDelegate().send(urlRequest, bodyFileURL: request.bodyFileURL,
                configuration: configuration)
        } catch let error as HTTPTransportError {
            throw error
        } catch {
            throw HTTPTransportError.network
        }
    }
}

private final class BoundedUploadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var accumulator = BoundedResponseAccumulator(limit: DeliveryTimeouts.maximumErrorExcerptBytes)
    private var response: HTTPURLResponse?
    private var continuation: CheckedContinuation<HTTPResponse, Error>?
    private var retainedSession: URLSession?

    func send(_ request: URLRequest, bodyFileURL: URL,
              configuration: URLSessionConfiguration) async throws -> HTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            lock.withLock { retainedSession = session }
            session.uploadTask(with: request, fromFile: bodyFileURL).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        lock.withLock { self.response = response as? HTTPURLResponse }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.withLock { accumulator.append(data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let completion: (CheckedContinuation<HTTPResponse, Error>, Result<HTTPResponse, Error>)? = lock.withLock {
            guard let continuation else { return nil }
            self.continuation = nil
            retainedSession = nil
            if error != nil { return (continuation, .failure(HTTPTransportError.network)) }
            guard let response else { return (continuation, .failure(HTTPTransportError.invalidResponse)) }
            let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                if let key = entry.key as? String { result[key] = String(describing: entry.value) }
            }
            return (continuation, .success(HTTPResponse(statusCode: response.statusCode,
                headers: headers, body: accumulator.data)))
        }
        session.finishTasksAndInvalidate()
        if let completion { completion.0.resume(with: completion.1) }
    }
}
