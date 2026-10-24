import Foundation

// What the iPhone's agent sheet reads from Hath beyond the threads and roster in Hath.swift, which the watch also compiles.

/// A tool an agent is granted, from GET /agents/:id.
struct AgentTool: Decodable, Sendable, Hashable {
    let name: String
    let description: String
    let usage: String
}

/// GET /agents/:id: the agent and the tools it is granted.
struct AgentDetail: Decodable, Sendable {
    let agent: AgentRecord
    let tools: [AgentTool]

    private enum Keys: String, CodingKey { case tools }

    init(from decoder: Decoder) throws {
        agent = try AgentRecord(from: decoder)
        tools = try decoder.container(keyedBy: Keys.self).decode([AgentTool].self, forKey: .tools)
    }
}

/// What a log row records.
enum LogEvent: String, Decodable, Sendable, Hashable {
    case response
    case toolResult = "tool_result"
    case message
}

/// One durable log row from GET /agents/:id/logs. Decoded verbatim
/// (`ServiceJSON.verbatim`), since payload keys are the agent's own and must
/// not be camel-cased.
struct LogRecord: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let agentId: String
    let lane: Lane
    let event: LogEvent
    let payload: [String: JSONValue]
    /// The wake that wrote the row; nil for rows from before wake ids.
    let wakeId: String?
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, lane, event, payload
        case agentId = "agent_id"
        case wakeId = "wake_id"
        case createdAt = "created_at"
    }
}

/// A message Hath delivers from one agent to another at `runAt`, optionally
/// repeating.
struct ScheduledMessage: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let fromAgentId: String
    let toAgentId: String
    let content: String
    /// The next delivery.
    let runAt: Date
    /// Nil delivers once.
    let intervalMinutes: Int?
    let createdAt: Date
}

/// Body of PATCH /schedules/:id: only what changes.
struct PatchScheduleRequest: Encodable, Sendable {
    /// How a schedule repeats after the change.
    enum Repeat: Sendable, Equatable {
        case once
        case every(minutes: Int)
    }

    var runAt: Date?
    var content: String?
    var repeats: Repeat?

    private enum Keys: String, CodingKey { case runAt, content, intervalMinutes }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encodeIfPresent(runAt, forKey: .runAt)
        try c.encodeIfPresent(content, forKey: .content)
        switch repeats {
        case .once: try c.encodeNil(forKey: .intervalMinutes)
        case .every(let minutes): try c.encode(minutes, forKey: .intervalMinutes)
        case nil: break
        }
    }
}
