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
}
