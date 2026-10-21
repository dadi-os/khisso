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

    /// POST /planner/query: the day plan's blocks overlapping [from, to), earliest first.
    func planner(from: Date, to: Date) async throws -> [PlannerBlock] {
        struct Response: Decodable { let blocks: [PlannerBlock] }
        let response: Response = try await client.post("/planner/query", body: PlannerQuery(from: from, to: to))
        return response.blocks
    }

    /// PATCH /planner/blocks/:id: marks a block done or open again.
    func setDone(_ done: Bool, block id: String) async throws -> PlannerBlock {
        try await client.patch("/planner/blocks/\(id)", body: PlannerDone(done: done))
    }

    /// POST /ingest: Yaad reads `text` and remembers what it says.
    func ingest(_ text: String) async throws -> IngestResponse {
        try await client.post("/ingest", body: IngestRequest(text: text, occurredAt: .now), timeout: Self.ingestTimeout)
    }
}
