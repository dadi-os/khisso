import Foundation

/// A plan's state: an idea has no date yet; tentative and confirmed are on the timeline.
enum PlanStatus: String, Codable, Sendable {
    case idea
    case tentative
    case confirmed
}

/// What a plan is, as Yaad's timeline names it; commitments stand out, routines stay quiet.
enum PlanKind: String, Decodable, Sendable, Hashable {
    case `class`, lab, exam, task, meeting, appointment, reservation, social, trip, bill
    case meal, shower, gym, study, focus

    /// Meals, showers, gym, study and focus blocks: time laid out around the commitments.
    var isRoutine: Bool {
        switch self {
        case .meal, .shower, .gym, .study, .focus: true
        default: false
        }
    }

    /// The kind in a word, for a session's sheet.
    var label: String {
        switch self {
        case .class: "Class"
        case .lab: "Lab"
        case .exam: "Exam"
        case .task: "Task"
        case .meeting: "Meeting"
        case .appointment: "Appointment"
        case .reservation: "Reservation"
        case .social: "Social"
        case .trip: "Trip"
        case .bill: "Bill"
        case .meal: "Meal"
        case .shower: "Shower"
        case .gym: "Gym"
        case .study: "Study"
        case .focus: "Focus"
        }
    }
}

/// Which filter Yaad's `POST /timeline` applies.
enum TimelineViewName: String, Encodable, Sendable {
    case planner, due, month, someday, tile
}

/// A memory attached to one session: what it covered, what to follow up.
struct SessionNote: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let body: String?
}

/// Where a plan happens: its place, with the room its edge names.
struct TimelinePlace: Decodable, Sendable, Hashable {
    let id: String
    let title: String
    /// A full street address, which Apple Maps opens directions to.
    let address: String?
    let room: String?
}

/// Sessions completed and held so far in a series.
struct SeriesCount: Decodable, Sendable, Hashable {
    let completed: Int
    let total: Int
}

/// One session of a plan as a timeline view shows it.
struct TimelineItem: Decodable, Sendable, Hashable, Identifiable {
    /// The plan's node id, shared by every session of a series.
    let planId: String
    /// The local date (YYYY-MM-DD) the session was first scheduled for; nil for an undated idea.
    let occurrenceDate: String?
    let title: String
    let body: String?
    let kind: PlanKind?
    let status: PlanStatus
    /// Session times with any move applied; nil for a deadline with no time set aside.
    let startAt: Date?
    let endAt: Date?
    let dueAt: Date?
    let opensAt: Date?
    let allDay: Bool
    let hideFromPlanner: Bool
    /// scheduled, moved or cancelled.
    let state: String
    /// done or missed; nil while nobody has said.
    let outcome: String?
    /// The plan's rule in words ("every Tue and Thu"); nil for a one-off plan.
    let recurrence: String?
    let series: SeriesCount?
    let place: TimelinePlace?
    /// The agent that keeps it, or `manual` / `ingest` when no agent does.
    let owner: String
    let notes: [SessionNote]

    /// A session is named by its plan and its date.
    var id: String { "\(planId):\(occurrenceDate ?? "undated")" }

    var completed: Bool { outcome == "done" }
    var missed: Bool { outcome == "missed" }
    var cancelled: Bool { state == "cancelled" }

    /// The agent to message about it; nil when no agent keeps it.
    var ownerAgent: String? { owner == "manual" || owner == "ingest" ? nil : owner }

    /// When it is: its start, else its due.
    var when: Date? { startAt ?? dueAt }

    private enum CodingKeys: String, CodingKey {
        case planId = "id"
        case occurrenceDate, title, body, kind, status, startAt, endAt, dueAt, opensAt, allDay, hideFromPlanner
        case state, outcome, recurrence, series, place, owner, notes
    }

    /// This session with Ankur's Completed mark set or taken back, shown before Yaad confirms it.
    func marked(completed: Bool) -> TimelineItem {
        TimelineItem(
            planId: planId, occurrenceDate: occurrenceDate, title: title, body: body, kind: kind, status: status,
            startAt: startAt, endAt: endAt, dueAt: dueAt, opensAt: opensAt, allDay: allDay, hideFromPlanner: hideFromPlanner,
            state: state, outcome: completed ? "done" : nil, recurrence: recurrence, series: series, place: place,
            owner: owner, notes: notes
        )
    }
}

/// Body of POST /timeline: sessions in [from, to) through one view.
struct TimelineQuery: Encodable, Sendable {
    let from: Date
    let to: Date
    let view: TimelineViewName
}

/// Body of PUT /timeline/outcome: Ankur's one hand write, a session marked completed or the mark taken back.
struct OutcomeRequest: Encodable, Sendable {
    let planId: String
    let occurrenceDate: String
    /// "done", or nil, sent as null, to take the mark back.
    let outcome: String?

    private enum CodingKeys: String, CodingKey {
        case planId, occurrenceDate, outcome
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(planId, forKey: .planId)
        try container.encode(occurrenceDate, forKey: .occurrenceDate)
        try container.encode(outcome, forKey: .outcome)
    }
}

/// PUT /timeline/outcome: the session's outcome as Yaad saved it.
struct OutcomeResponse: Decodable, Sendable {
    let outcome: String?
}
