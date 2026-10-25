import Foundation

/// Yaad, dadi's memory: the timeline's views over its plans, and the one
/// thing this app writes to it, Ankur's Completed mark.
struct YaadClient: Sendable {
    /// Yaad's address on dadi, served by Caddy on the box.
    static let baseURL = URL(string: "http://yaad.dadi")!

    let client: ServiceClient

    init(session: URLSession) {
        client = ServiceClient(session: session, baseURL: Self.baseURL)
    }

    /// POST /timeline: the sessions in [from, to) through `view`, earliest first.
    func timeline(_ view: TimelineViewName, from: Date, to: Date) async throws -> [TimelineItem] {
        struct Response: Decodable { let items: [TimelineItem] }
        let response: Response = try await client.post("/timeline", body: TimelineQuery(from: from, to: to, view: view))
        return response.items
    }

    /// PUT /timeline/outcome: marks the session of `plan` first scheduled on
    /// `date` (YYYY-MM-DD) completed, or takes the mark back.
    func setCompleted(_ completed: Bool, plan: String, on date: String) async throws -> OutcomeResponse {
        try await client.put("/timeline/outcome", body: OutcomeRequest(planId: plan, occurrenceDate: date, outcome: completed ? "done" : nil))
    }

    /// GET /events: one element per write to Yaad's plans or memories.
    func changes() async throws -> AsyncThrowingStream<Void, Error> {
        try await client.changes("/events")
    }
}
