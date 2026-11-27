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

    /// Like `decoder` but keeping keys as sent, for payloads whose keys are
    /// data rather than field names.
    static let verbatim: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = decoder.dateDecodingStrategy
        return d
    }()

    /// Like `encoder` but keeping keys as written, for a service whose bodies
    /// are camelCase, as Chaavi's are.
    static let verbatimEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = encoder.dateEncodingStrategy
        return e
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
    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], timeout: TimeInterval = 30, decoder: JSONDecoder = ServiceJSON.decoder) async throws -> T {
        try await send(request("GET", path, query: query, timeout: timeout), decoder: decoder)
    }

    /// Opens `path` and returns its body as it arrives. It fails once `idle`
    /// seconds pass without a byte.
    func bytes(_ path: String, query: [URLQueryItem] = [], idle: TimeInterval) async throws -> URLSession.AsyncBytes {
        let (bytes, response) = try await session.bytes(for: request("GET", path, query: query, timeout: idle))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw Self.error(status: status, body: body)
        }
        return bytes
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

    /// GET `path` into a file named `filename` in a fresh temporary folder and return its URL, so QuickLook and Share show
    /// the real name. The caller owns the file.
    func download(_ path: String, query: [URLQueryItem] = [], filename: String, timeout: TimeInterval) async throws -> URL {
        let (temporary, response) = try await session.download(for: request("GET", path, query: query, timeout: timeout))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = (try? Data(contentsOf: temporary)) ?? Data()
            try? FileManager.default.removeItem(at: temporary)
            throw Self.error(status: status, body: body)
        }
        let folder = URL.temporaryDirectory.appending(path: "downloads/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: filename, directoryHint: .notDirectory)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    /// POST the file at `file` to `path` as multipart form data, after `fields` in order, and decode the response as `T`.
    /// The body is assembled on disk and streamed, so a large file is never held in memory.
    func upload<T: Decodable>(_ path: String, fields: [(name: String, value: String)], file: URL, filename: String, mediaType: String, timeout: TimeInterval) async throws -> T {
        let boundary = "dadi-\(UUID().uuidString)"
        let body = URL.temporaryDirectory.appending(path: "upload-\(UUID().uuidString)", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: body) }
        try Self.writeMultipart(to: body, boundary: boundary, fields: fields, file: file, filename: filename, mediaType: mediaType)
        var req = request("POST", path, timeout: timeout)
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: req, fromFile: body)
        return try decode(data, response, req)
    }

    private static func writeMultipart(to body: URL, boundary: String, fields: [(name: String, value: String)], file: URL, filename: String, mediaType: String) throws {
        FileManager.default.createFile(atPath: body.path(percentEncoded: false), contents: nil)
        let out = try FileHandle(forWritingTo: body)
        defer { try? out.close() }
        func quoted(_ value: String) -> String {
            value.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"").replacing("\r", with: "").replacing("\n", with: "")
        }
        for field in fields {
            try out.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(quoted(field.name))\"\r\n\r\n\(field.value)\r\n".utf8))
        }
        try out.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(quoted(filename))\"\r\nContent-Type: \(mediaType)\r\n\r\n".utf8))
        let source = try FileHandle(forReadingFrom: file)
        defer { try? source.close() }
        while let chunk = try source.read(upToCount: 1 << 20), !chunk.isEmpty {
            try out.write(contentsOf: chunk)
        }
        try out.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }

    /// POST `body` as JSON to `path` and decode the response as `T`.
    func post<B: Encodable, T: Decodable>(_ path: String, body: B, timeout: TimeInterval = 30, encoder: JSONEncoder = ServiceJSON.encoder) async throws -> T {
        var req = request("POST", path, timeout: timeout)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        return try await send(req)
    }

    /// PATCH `body` as JSON to `path` and decode the response as `T`.
    func patch<B: Encodable, T: Decodable>(_ path: String, body: B, timeout: TimeInterval = 30, encoder: JSONEncoder = ServiceJSON.encoder) async throws -> T {
        var req = request("PATCH", path, timeout: timeout)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        return try await send(req)
    }

    /// PUT `body` as JSON to `path` and decode the response as `T`.
    func put<B: Encodable, T: Decodable>(_ path: String, body: B, timeout: TimeInterval = 30) async throws -> T {
        var req = request("PUT", path, timeout: timeout)
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

    /// DELETE `path` for a response with no body (204).
    func delete(_ path: String, timeout: TimeInterval = 30) async throws {
        let (data, response) = try await session.data(for: request("DELETE", path, timeout: timeout))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Self.error(status: status, body: data)
        }
    }

    /// A service's change stream at `path`: one element per event it sends, each
    /// meaning "something changed, read again". Services ping every 20 s, so
    /// the stream fails after 45 quiet seconds rather than hang on a dead
    /// connection.
    func changes(_ path: String) async throws -> AsyncThrowingStream<Void, Error> {
        let lines = try await lines(path, idle: 45)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in lines where line.hasPrefix("data:") {
                        continuation.yield()
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Opens a Server-Sent Events stream at `path` and returns its lines. It
    /// fails once `idle` seconds pass with nothing from the server, so a
    /// connection that died while the app was suspended or the network changed
    /// is noticed instead of waited on forever.
    func lines(_ path: String, idle: TimeInterval) async throws -> AsyncLineSequence<URLSession.AsyncBytes> {
        var req = request("GET", path, timeout: idle)
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

    /// What a request path may hold as written: path characters and the `%` of a segment the caller already escaped, such as the `%2F` of a task address.
    private static let encodedPath = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: "%"))

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], timeout: TimeInterval) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = path.addingPercentEncoding(withAllowedCharacters: Self.encodedPath)!
        if !query.isEmpty {
            components.queryItems = query
            components.percentEncodedQuery = components.percentEncodedQuery?.replacing("+", with: "%2B")
        }
        var req = URLRequest(url: components.url!, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Request-Id")
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, decoder: JSONDecoder = ServiceJSON.decoder) async throws -> T {
        let (data, response) = try await session.data(for: req)
        return try decode(data, response, req, decoder: decoder)
    }

    private func decode<T: Decodable>(_ data: Data, _ response: URLResponse, _ req: URLRequest, decoder: JSONDecoder = ServiceJSON.decoder) throws -> T {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Self.error(status: status, body: data)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch let problem as DecodingError {
            throw ServiceError(status: status, type: "unexpected_response", message: "\(req.url?.path ?? "The service") answered in a shape dadi does not understand: \(Self.describe(problem))")
        }
    }

    /// What a decode failure is about: the missing key or wrong type, and where it is in the reply.
    nonisolated static func describe(_ error: DecodingError) -> String {
        func at(_ path: [CodingKey]) -> String { path.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined() }
        switch error {
        case .keyNotFound(let key, let context): return "missing \"\(key.stringValue)\" at \(at(context.codingPath))"
        case .valueNotFound(_, let context): return "no value at \(at(context.codingPath))"
        case .typeMismatch(_, let context), .dataCorrupted(let context): return "\(context.debugDescription) at \(at(context.codingPath))"
        @unknown default: return "unreadable reply"
        }
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
