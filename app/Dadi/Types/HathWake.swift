import Foundation

// Wakes as Hath's GET /agents/:id/wakes routes return them. Decoded with
// `ServiceJSON.verbatim` and explicit keys, since a tool call's input keys are
// the agent's own and must not be camel-cased.

/// Why a wake began.
enum WakeReasonKind: String, Decodable, Sendable, Hashable {
    case message
    case schedule
    case recovery
    case steer
    case manual
}

/// The structured reason a wake began.
struct WakeReason: Decodable, Sendable, Hashable {
    let kind: WakeReasonKind
    /// The sender agent id for a message (nil for Ankur), the schedule id for a schedule, else nil.
    let ref: String?
}

/// Where a wake stands. `waiting` appears only on an agent's latest wake, when its work lane watches a task or agent.
enum WakeOutcome: String, Decodable, Sendable, Hashable {
    case running
    case waiting
    case yielded
    case failed
}

/// Model usage summed over a wake's model calls.
struct WakeUsage: Decodable, Sendable, Hashable {
    /// How many model calls.
    let calls: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheWrite: Int
    let cacheRead: Int

    private enum CodingKeys: String, CodingKey {
        case calls
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheWrite = "cache_write"
        case cacheRead = "cache_read"
    }
}

/// What a wake did, counted.
struct WakeCounts: Decodable, Sendable, Hashable {
    let toolCalls: Int
    let messagesSent: Int
    let messagesReceived: Int

    private enum CodingKeys: String, CodingKey {
        case toolCalls = "tool_calls"
        case messagesSent = "messages_sent"
        case messagesReceived = "messages_received"
    }
}

/// A message as the wake routes return it; its attachments are not read.
struct WakeMessage: Decodable, Sendable, Hashable {
    let id: String
    let seq: Int
    /// Nil when Ankur sent it.
    let fromAgentId: String?
    /// Nil when it was sent to Ankur.
    let toAgentId: String?
    let content: String
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, seq, content
        case fromAgentId = "from_agent_id"
        case toAgentId = "to_agent_id"
        case createdAt = "created_at"
    }
}

/// One wake as GET /agents/:id/wakes lists it and GET /agents/:id/wakes/:wake_id opens it.
struct WakeSummary: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let agentId: String
    let reason: WakeReason
    /// The message that opened the wake, when one did.
    let openedBy: WakeMessage?
    let startedAt: Date
    /// Nil while a lane run is queued or running.
    let endedAt: Date?
    let outcome: WakeOutcome
    /// Set when the outcome is `failed`.
    let error: String?
    let usage: WakeUsage
    let counts: WakeCounts
    /// True when the wake's activity aged out; its messages remain.
    let activityTrimmed: Bool

    private enum CodingKeys: String, CodingKey {
        case id, reason, outcome, error, usage, counts
        case agentId = "agent_id"
        case openedBy = "opened_by"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case activityTrimmed = "activity_trimmed"
    }
}

/// A tool call's result inside a wake.
struct WakeToolResult: Decodable, Sendable, Hashable {
    /// Cut to the server cap when `truncated`.
    let content: String
    let isError: Bool
    let truncated: Bool
    /// The result's full length in characters.
    let chars: Int

    private enum CodingKeys: String, CodingKey {
        case content, truncated, chars
        case isError = "is_error"
    }
}

/// One tool call of a turn, paired with its result.
struct WakeToolCall: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let input: JSONValue
    /// The result's raw log row; nil until the result is logged.
    let logId: String?
    /// Nil until the tool's result is logged.
    let result: WakeToolResult?

    private enum CodingKeys: String, CodingKey {
        case id, name, input, result
        case logId = "log_id"
    }
}

/// A message the agent received or sent, as an entry of a wake.
struct WakeMessageEntry: Decodable, Sendable, Hashable {
    enum Direction: String, Decodable, Sendable, Hashable {
        case sent
        case received
    }

    let ord: Int
    let at: Date
    let direction: Direction
    let message: WakeMessage
}

/// One model turn, as an entry of a wake.
struct WakeTurn: Decodable, Sendable, Hashable {
    let ord: Int
    let at: Date
    let lane: Lane
    let thinking: String?
    let text: String?
    let calls: [WakeToolCall]
}

/// One entry of a wake's timeline, ordered by `ord`.
enum WakeEntry: Decodable, Sendable, Hashable, Identifiable {
    case message(WakeMessageEntry)
    case turn(WakeTurn)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let type = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .type)
        switch type {
        case "message": self = .message(try WakeMessageEntry(from: decoder))
        case "turn": self = .turn(try WakeTurn(from: decoder))
        default: throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown wake entry type: \(type)"))
        }
    }

    var ord: Int {
        switch self {
        case .message(let entry): entry.ord
        case .turn(let turn): turn.ord
        }
    }

    var id: Int { ord }
}

/// The keyset position after the last wake of a page. Kept as sent, so the next page starts exactly there.
struct WakeCursor: Decodable, Sendable, Hashable {
    let startedAt: String
    let id: String

    private enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at"
    }
}

/// GET /agents/:id/wakes: one page, newest first; `nextBefore` is nil at the end.
struct WakePage: Decodable, Sendable {
    let wakes: [WakeSummary]
    let nextBefore: WakeCursor?

    private enum CodingKeys: String, CodingKey {
        case wakes
        case nextBefore = "next_before"
    }
}

/// GET /agents/:id/wakes/:wake_id: the wake with its messages and model turns in order.
struct WakeDetail: Decodable, Sendable {
    let wake: WakeSummary
    let entries: [WakeEntry]
}

/// GET /agents/:id/logs/:log_id.
struct LogResponse: Decodable, Sendable {
    let log: LogRecord
}
