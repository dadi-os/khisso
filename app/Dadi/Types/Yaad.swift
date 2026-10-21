import Foundation

/// A plan's state: an idea has no date yet; tentative and confirmed are on the timeline.
enum PlanStatus: String, Codable, Sendable {
    case idea
    case tentative
    case confirmed
}

/// The plan fields of a Yaad node's detail.
struct PlanDetail: Decodable, Sendable, Hashable {
    let endAt: Date?
    /// The plan has a date but no time of day.
    let allDay: Bool
    let status: PlanStatus
    let recurrence: String?
}

/// A plan from POST /query with kind plan.
struct PlanNode: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let body: String?
    /// When it starts; nil for an idea.
    let occurredAt: Date?
    /// The Hath agent that made it, if an agent did.
    let agentId: String?
    let detail: PlanDetail
}

/// Body of POST /query for plans in a window.
struct PlanQuery: Encodable, Sendable {
    let kind = "plan"
    let occurredFrom: Date
    let occurredTo: Date
    let limit: Int
}

/// Body of POST /ingest: words for Yaad to remember, read relative to `occurredAt`.
struct IngestRequest: Encodable, Sendable {
    let text: String
    let occurredAt: Date
    let source = "ingest"
}

/// POST /ingest: how many of each operation Yaad applied.
struct IngestResponse: Decodable, Sendable {
    let counts: [String: Int]
}
