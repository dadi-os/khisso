import Foundation

/// One timed block of the day plan from Yaad's planner (POST /planner/query).
struct PlannerBlock: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let startAt: Date
    let endAt: Date
    let title: String
    let note: String?
    /// meal, class, exam, study, gym, shower, recruiting, fixed, and older wake, free, lights_out.
    let kind: String
    /// sun, cup, fork, book, pulse, drop, brief, leaf, moon, flag, pencil, walk, users or phone.
    let icon: String
    /// The block never moves or shrinks to make room.
    let fixed: Bool
    /// When it was marked done; nil while open.
    let doneAt: Date?
}

/// Body of POST /planner/query: blocks overlapping [from, to).
struct PlannerQuery: Encodable, Sendable {
    let from: Date
    let to: Date
}

/// Body of PATCH /planner/blocks/:id.
struct PlannerDone: Encodable, Sendable {
    let done: Bool
}
