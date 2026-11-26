import Foundation

/// Ankur's answer to a plan, as Yaad holds it; nil until he has answered.
enum Rsvp: String, Decodable, Sendable, Hashable {
    case yes, no
}

/// A memory attached to one plan: what was covered, what to follow up.
struct PlanNote: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let body: String?
}

/// Where a plan happens: its place, with the room its edge names.
struct PlanPlace: Decodable, Sendable, Hashable {
    let id: String
    let title: String
    /// A full street address, which Apple Maps opens directions to.
    let address: String?
    let room: String?
}

/// The course a plan or task belongs to.
struct Hub: Decodable, Sendable, Hashable {
    let id: String
    let title: String
}

/// One plan as Yaad holds it, declined ones included.
struct Plan: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let body: String?
    let rsvp: Rsvp?
    let startAt: Date
    /// nil for a plan with no end.
    let endAt: Date?
    let allDay: Bool
    let timeZone: String?
    /// Whether Ankur was there; nil until he says.
    let attended: Bool?
    let place: PlanPlace?
    let hub: Hub?
    /// The plan's agent id, else its source (`manual`, `ingest`).
    let owner: String
    let notes: [PlanNote]

    var declined: Bool { rsvp == .no }

    /// This plan with Ankur's attendance answer set or cleared.
    func answered(attended: Bool?) -> Plan {
        Plan(id: id, title: title, body: body, rsvp: rsvp, startAt: startAt, endAt: endAt, allDay: allDay, timeZone: timeZone, attended: attended, place: place, hub: hub, owner: owner, notes: notes)
    }
}

/// One task as the checklist shows it.
struct PlanTask: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let body: String?
    /// The local date (YYYY-MM-DD) the task opens; nil when it has no window.
    let opensOn: String?
    /// When the task closes; a date-only close arrives as 23:59 local. nil when open-ended.
    let closesAt: Date?
    let done: Bool
    let verifiedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    /// Its close has passed and it is not done.
    let pastDue: Bool
    let hub: Hub?
    let owner: String

    /// This task with its done flag set.
    func marked(done: Bool) -> PlanTask {
        PlanTask(id: id, title: title, body: body, opensOn: opensOn, closesAt: closesAt, done: done, verifiedAt: verifiedAt, createdAt: createdAt, updatedAt: updatedAt, pastDue: pastDue, hub: hub, owner: owner)
    }
}

/// Body of POST /planner/plans: every plan touching [from, to).
struct PlansQuery: Encodable, Sendable {
    let from: Date
    let to: Date
}

/// Body of POST /planner/tasks: a local day's checklist, or the tasks with no window.
struct TasksQuery: Encodable, Sendable {
    let on: String?
    let someday: Bool?

    static func day(_ key: String) -> TasksQuery { TasksQuery(on: key, someday: nil) }
    static let someday = TasksQuery(on: nil, someday: true)
}

/// Body of PUT /planner/tasks/done: Ankur ticks a task or takes the tick back.
struct TaskDoneRequest: Encodable, Sendable {
    let taskId: String
    let done: Bool
}

/// PUT /planner/tasks/done: the flag Yaad saved.
struct TaskDoneResponse: Decodable, Sendable {
    let taskId: String
    let done: Bool
}

/// Body of PUT /planner/plans/attended: whether Ankur was at a plan, or null to clear it.
struct AttendedRequest: Encodable, Sendable {
    let planId: String
    let attended: Bool?

    private enum CodingKeys: String, CodingKey {
        case planId, attended
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(planId, forKey: .planId)
        try container.encode(attended, forKey: .attended)
    }
}

/// PUT /planner/plans/attended: the answer Yaad saved.
struct AttendedResponse: Decodable, Sendable {
    let planId: String
    let attended: Bool?
}

/// GET /counts: how many nodes Yaad keeps, in total and by kind.
struct YaadCounts: Decodable, Sendable, Equatable {
    struct Kinds: Decodable, Sendable, Equatable {
        let person: Int
        let memory: Int
        let place: Int
        let plan: Int
        let task: Int
    }

    let total: Int
    let kinds: Kinds
}
