import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct TransportRequest: Hashable, Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data
    /// Seconds to wait for the answer; nil uses the transport's default.
    public var timeout: TimeInterval?

    public init(url: URL, method: String, headers: [String: String], body: Data, timeout: TimeInterval? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct TransportResponse: Hashable, Sendable {
    public var status: Int
    /// Header names are lowercased.
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// One HTTP exchange. Throws only when no HTTP answer arrived (offline, DNS, timeout).
public protocol HTTPTransport: Sendable {
    func send(_ request: TransportRequest) async throws -> TransportResponse
}

/// The real transport. Works on Linux through FoundationNetworking.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 600) {
        self.session = session
        self.timeout = timeout
    }

    /// The `URLRequest` for one exchange: the request's own timeout wins over the transport's default.
    public func urlRequest(for request: TransportRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout ?? timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        return urlRequest
    }

    public func send(_ request: TransportRequest) async throws -> TransportResponse {
        let (data, response) = try await session.data(for: urlRequest(for: request))
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            if let name = name as? String, let value = value as? String { headers[name] = value }
        }
        return TransportResponse(status: http.statusCode, headers: headers, body: data)
    }
}
