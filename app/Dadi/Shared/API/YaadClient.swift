import Foundation

/// Yaad, dadi's memory: plans for the timeline and ingest for new memories.
struct YaadClient: Sendable {
    /// Yaad's address on dadi, served by Caddy on the box.
    static let baseURL = URL(string: "http://yaad.dadi")!

    /// Ingest runs a reasoning call inside Yaad, which waits up to 330 s on Dwar.
    static let ingestTimeout: TimeInterval = 360

    let client: ServiceClient

    init(session: URLSession) {
        client = ServiceClient(session: session, baseURL: Self.baseURL)
    }

    /// POST /query: dated plans starting in [from, to), ideas excluded.
    func plans(from: Date, to: Date) async throws -> [PlanNode] {
        struct Response: Decodable { let nodes: [PlanNode] }
        let response: Response = try await client.post("/query", body: PlanQuery(occurredFrom: from, occurredTo: to, limit: 200))
        return response.nodes.filter { $0.detail.status != .idea && $0.occurredAt != nil }
    }

    /// POST /ingest: Yaad reads `text` and remembers what it says.
    func ingest(_ text: String) async throws -> IngestResponse {
        try await client.post("/ingest", body: IngestRequest(text: text, occurredAt: .now), timeout: Self.ingestTimeout)
    }
}
