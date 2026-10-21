import Foundation

/// GET /health: Hath's process liveness.
struct HathHealth: Decodable, Sendable {
    let status: String
    /// When this Hath process started; identifies the process, not chat history.
    let startedAt: Date
}

/// A file a message carries; its bytes are GET /attachments/:id.
struct AttachmentSummary: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let filename: String
    let mediaType: String
    let sizeBytes: Int
    /// What an image shows; nil for other files.
    let description: String?
}

/// One human↔agent conversation from GET /threads.
struct ThreadSummary: Decodable, Sendable, Hashable, Identifiable {
    let agentId: String
    let agentName: String
    let lastMessage: String
    let lastAt: Date
    /// True when Ankur sent the last message.
    let fromUser: Bool

    var id: String { agentId }
}

/// One durable message in a human thread, from GET /agents/:id/messages.
struct DurableMessage: Decodable, Sendable, Hashable, Identifiable {
    /// A notice is Hath's word that an agent's work stopped, shown as a system line.
    enum Kind: String, Decodable, Sendable {
        case message
        case notice
    }

    /// Hath's ordering of messages; also identifies a message across history and events.
    let seq: Int
    /// Nil when Ankur sent it.
    let fromAgentId: String?
    /// Nil when it was sent to Ankur.
    let toAgentId: String?
    let content: String
    let attachments: [AttachmentSummary]
    /// Absent from an older Hath; treated as a message.
    let kind: Kind?
    let createdAt: Date

    var id: Int { seq }
    var fromUser: Bool { fromAgentId == nil }
}

/// One message the router sent to an agent as Ankur.
struct RoutedMessage: Decodable, Sendable, Hashable {
    let toAgentId: String
    let content: String
    let attachments: [AttachmentSummary]
    let seq: Int
    let createdAt: Date
}

/// POST /router: every message the router sent, in order; may be empty.
struct PostRouterResponse: Decodable, Sendable {
    let messages: [RoutedMessage]
}

/// POST /messages: the delivered message.
struct PostMessageResponse: Decodable, Sendable {
    let toAgentId: String
    let content: String
    let attachments: [AttachmentSummary]
    let seq: Int
    let createdAt: Date
}

/// Body of POST /router.
struct RouterRequest: Encodable, Sendable {
    let content: String
}

/// Body of POST /messages.
struct MessageRequest: Encodable, Sendable {
    let toAgentId: String
    let content: String
}

/// One event from Hath's GET /events stream. Event types this app does not act
/// on yet decode as `unhandled` so the stream keeps going.
enum HathEvent: Decodable, Sendable, Equatable {
    /// A message entered a human thread.
    case message(agentId: String, message: DurableMessage)
    case laneStarted(agentId: String)
    case laneFinished(agentId: String)
    case laneFailed(agentId: String, message: String)
    case routerStarted
    case routerFinished
    case routerFailed(message: String)
    case unhandled(type: String)

    private enum Keys: String, CodingKey {
        case type, agentId, fromAgentId, toAgentId, content, attachments, seq, kind, at, message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "message":
            let seq = try c.decode(Int.self, forKey: .seq)
            let agentId = try c.decode(String.self, forKey: .agentId)
            self = .message(agentId: agentId, message: DurableMessage(
                seq: seq,
                fromAgentId: try c.decodeIfPresent(String.self, forKey: .fromAgentId),
                toAgentId: try c.decodeIfPresent(String.self, forKey: .toAgentId),
                content: try c.decode(String.self, forKey: .content),
                attachments: try c.decode([AttachmentSummary].self, forKey: .attachments),
                kind: try c.decodeIfPresent(DurableMessage.Kind.self, forKey: .kind),
                createdAt: try c.decode(Date.self, forKey: .at)
            ))
        case "lane_started":
            self = .laneStarted(agentId: try c.decode(String.self, forKey: .agentId))
        case "lane_finished":
            self = .laneFinished(agentId: try c.decode(String.self, forKey: .agentId))
        case "lane_failed":
            self = .laneFailed(
                agentId: try c.decode(String.self, forKey: .agentId),
                message: try c.decode(String.self, forKey: .message)
            )
        case "router_started":
            self = .routerStarted
        case "router_finished":
            self = .routerFinished
        case "router_failed":
            self = .routerFailed(message: try c.decode(String.self, forKey: .message))
        default:
            self = .unhandled(type: type)
        }
    }
}

/// One agent from GET /agents: the flat roster, each naming the agent that
/// made it.
struct AgentRecord: Decodable, Sendable, Hashable, Identifiable {
    /// What an agent is doing: thinking through work, or in a conversation.
    struct Running: Decodable, Sendable, Hashable {
        let reasoning: Bool
        let conversation: Bool
    }

    /// The browsers and terminals an agent holds open.
    struct Sessions: Decodable, Sendable, Hashable {
        struct Terminal: Decodable, Sendable, Hashable {
            let id: String
            let lastCommand: String?
        }

        let browsers: [Int]
        let terminals: [Terminal]
    }

    let id: String
    let name: String
    let systemPrompt: String
    /// Nil for a top-level agent.
    let parentAgentId: String?
    /// False once retired.
    let active: Bool
    let running: Running
    let sessions: Sessions
    let createdAt: Date
    let updatedAt: Date

    var isRunning: Bool { running.reasoning || running.conversation }
}
