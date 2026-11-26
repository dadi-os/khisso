import Foundation

// What the iPhone's agent sheet reads from Hath beyond the threads and roster in Hath.swift, which the watch also compiles.

/// GET /agents/:id: the agent.
struct AgentDetail: Decodable, Sendable {
    let agent: AgentRecord

    init(from decoder: Decoder) throws {
        agent = try AgentRecord(from: decoder)
    }
}

/// What a log row records.
enum LogEvent: String, Decodable, Sendable, Hashable {
    case response
    case toolResult = "tool_result"
}

/// One durable log row from GET /agents/:id/logs/:log_id. Decoded verbatim
/// (`ServiceJSON.verbatim`), since payload keys are the agent's own and must
/// not be camel-cased.
struct LogRecord: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let agentId: String
    let event: LogEvent
    let payload: [String: JSONValue]
    /// The wake that wrote the row; nil for rows from before wake ids.
    let wakeId: String?
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, event, payload
        case agentId = "agent_id"
        case wakeId = "wake_id"
        case createdAt = "created_at"
    }
}

/// Weekday names as a routine's `days` carry them.
enum Weekday: String, Decodable, Sendable, Hashable, CaseIterable {
    case mon, tue, wed, thu, fri, sat, sun
}

/// An agent's own standing duty: it runs at `at` on `days` and the agent changes it (`set_routine`); Ankur can
/// only cancel it.
struct Routine: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let agentId: String
    let title: String
    let procedure: String
    /// `HH:MM` in the box's zone.
    let at: String
    /// Nil is every day.
    let days: [Weekday]?
    let nextRunAt: Date
    let lastRunAt: Date?
    let active: Bool

    private enum CodingKeys: String, CodingKey { case id, agentId, title, procedure, at, days, nextRunAt, lastRunAt, active }

    init(id: String, agentId: String, title: String, procedure: String, at: String, days: [Weekday]?, nextRunAt: Date, lastRunAt: Date?, active: Bool) {
        self.id = id
        self.agentId = agentId
        self.title = title
        self.procedure = procedure
        self.at = at
        self.days = days
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
        self.active = active
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        agentId = try c.decode(String.self, forKey: .agentId)
        title = try c.decode(String.self, forKey: .title)
        procedure = try c.decode(String.self, forKey: .procedure)
        at = try c.decode(String.self, forKey: .at)
        days = try c.decodeIfPresent([Weekday].self, forKey: .days)
        nextRunAt = try c.decodeInstant(forKey: .nextRunAt)
        lastRunAt = try c.decodeInstantIfPresent(forKey: .lastRunAt)
        active = try c.decode(Bool.self, forKey: .active)
    }
}

/// A one-shot "check back at" that belongs to a job.
struct Reminder: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let agentId: String
    let note: String
    let runAt: Date

    private enum CodingKeys: String, CodingKey { case id, agentId, note, runAt }

    init(id: String, agentId: String, note: String, runAt: Date) {
        self.id = id
        self.agentId = agentId
        self.note = note
        self.runAt = runAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        agentId = try c.decode(String.self, forKey: .agentId)
        note = try c.decode(String.self, forKey: .note)
        runAt = try c.decodeInstant(forKey: .runAt)
    }
}

/// GET /agents/:id/routines: the agent's routines and reminders, next run first.
struct Routines: Decodable, Sendable, Hashable {
    let routines: [Routine]
    let reminders: [Reminder]
}

/// POST /agents/:id/stop: what Hath ended. `haltFailed` names each helper task it could not halt.
struct StopResult: Decodable, Sendable, Hashable {
    struct HaltFailure: Decodable, Sendable, Hashable {
        let task: String
        let error: String
    }

    let endedRun: Bool
    let stoppedTasks: [String]
    let haltFailed: [HaltFailure]
}
