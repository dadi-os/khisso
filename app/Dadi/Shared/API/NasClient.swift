import Foundation

/// Nas, the box itself: health, the devices on dadi, and its logs.
struct NasClient: Sendable {
    /// Nas's address on dadi, served by Caddy on the box.
    static let baseURL = URL(string: "http://nas.dadi")!

    let client: ServiceClient

    init(session: URLSession) {
        client = ServiceClient(session: session, baseURL: Self.baseURL)
    }

    /// GET /status.
    func status() async throws -> NasStatus {
        try await client.get("/status")
    }

    /// GET /clients: every device on dadi, and setup codes not yet used.
    func devices() async throws -> [NasClientDevice] {
        struct Response: Decodable { let clients: [NasClientDevice] }
        let response: Response = try await client.get("/clients")
        return response.clients
    }

    /// GET /logs at `level`, newest first.
    func logs(level: String, limit: Int) async throws -> [NasLogEntry] {
        struct Response: Decodable { let entries: [NasLogEntry] }
        let response: Response = try await client.get("/logs", query: [URLQueryItem(name: "level", value: level), URLQueryItem(name: "limit", value: String(limit))])
        return response.entries
    }

    /// GET /browsers: the headed browsers running now.
    func browsers() async throws -> [NasBrowser] {
        try await client.get("/browsers")
    }

    /// GET /terminals: the host terminal panes running now.
    func terminals() async throws -> [NasTerminal] {
        try await client.get("/terminals")
    }

    /// How a view wants a browser's stream: Nas's watch-only defaults, cheap
    /// enough to leave open.
    static let watch = (fps: 5, width: 960, kbps: 600)

    /// The stream may go this many seconds without a byte: the first frame
    /// waits on the encoder starting, and a still page sends little after.
    static let streamIdle: TimeInterval = 15

    /// GET /browsers/:id/stream: the browser's display as raw H.264 (Annex B).
    func browserStream(_ id: Int) async throws -> URLSession.AsyncBytes {
        try await client.bytes("/browsers/\(id)/stream", query: [
            URLQueryItem(name: "fps", value: String(Self.watch.fps)),
            URLQueryItem(name: "width", value: String(Self.watch.width)),
            URLQueryItem(name: "kbps", value: String(Self.watch.kbps)),
        ], idle: Self.streamIdle)
    }
}
