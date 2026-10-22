import Foundation

/// A failed call to a dadi service. `type` is the service's stable error code
/// from `{error:{type,message}}`; a response without that shape becomes
/// `unexpected_response` with the HTTP status and body.
struct ServiceError: LocalizedError, Sendable, Equatable {
    let status: Int
    let type: String
    let message: String

    var errorDescription: String? { message }
}

/// The JSON coding every dadi service uses: snake_case keys and ISO 8601 dates
/// with milliseconds.
enum ServiceJSON {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an ISO 8601 date: \(text)"))
            }
            return date
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return e
    }()
}

/// The HTTP client for one dadi service at `baseURL`, over `session`. Every
/// request carries an `X-Request-Id` and a timeout; failures throw
/// `ServiceError` with the service's own message.
struct ServiceClient: Sendable {
    let session: URLSession
    let baseURL: URL

    /// GET `path` and decode the response as `T`.
    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], timeout: TimeInterval = 30) async throws -> T {
        try await send(request("GET", path, query: query, timeout: timeout))
    }

    /// GET `path` and return the response body's bytes as they are.
    func data(_ path: String, timeout: TimeInterval = 30) async throws -> Data {
        let (data, response) = try await session.data(for: request("GET", path, timeout: timeout))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Self.error(status: status, body: data)
        }
        return data
    }

    /// POST `body` as JSON to `path` and decode the response as `T`.
    func post<B: Encodable, T: Decodable>(_ path: String, body: B, timeout: TimeInterval = 30) async throws -> T {
        var req = request("POST", path, timeout: timeout)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try ServiceJSON.encoder.encode(body)
        return try await send(req)
    }

    /// PATCH `body` as JSON to `path` and decode the response as `T`.
    func patch<B: Encodable, T: Decodable>(_ path: String, body: B, timeout: TimeInterval = 30) async throws -> T {
        var req = request("PATCH", path, timeout: timeout)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try ServiceJSON.encoder.encode(body)
        return try await send(req)
    }

    /// POSTs `body` as JSON to `path` for a response with no body (204).
    func send<B: Encodable>(_ path: String, body: B, timeout: TimeInterval = 30) async throws {
        var req = request("POST", path, timeout: timeout)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try ServiceJSON.encoder.encode(body)
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Self.error(status: status, body: data)
        }
    }

    /// Opens a Server-Sent Events stream at `path` and returns its lines. The
    /// request has no timeout; it ends when the server or the caller closes it.
    func lines(_ path: String) async throws -> AsyncLineSequence<URLSession.AsyncBytes> {
        var req = request("GET", path, timeout: .infinity)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw Self.error(status: status, body: body)
        }
        return bytes.lines
    }

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], timeout: TimeInterval) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty {
            url.append(queryItems: query)
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Request-Id")
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Self.error(status: status, body: data)
        }
        return try ServiceJSON.decoder.decode(T.self, from: data)
    }

    /// The service's error from a non-2xx response body.
    static func error(status: Int, body: Data) -> ServiceError {
        struct Envelope: Decodable {
            struct Inner: Decodable {
                let type: String
                let message: String
            }
            let error: Inner
        }
        if let envelope = try? ServiceJSON.decoder.decode(Envelope.self, from: body) {
            return ServiceError(status: status, type: envelope.error.type, message: envelope.error.message)
        }
        let text = String(decoding: body.prefix(300), as: UTF8.self)
        return ServiceError(status: status, type: "unexpected_response", message: "HTTP \(status): \(text)")
    }
}
