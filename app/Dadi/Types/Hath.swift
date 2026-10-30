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
    /// The agent's messages to Ankur he has not read, on any device.
    var unread: Int
    /// The last message he has read here; nil until he reads the thread.
    var readSeq: Int?

    var id: String { agentId }
}

/// POST /agents/:id/read: where the thread's read mark now stands.
struct ThreadRead: Decodable, Sendable {
    let agentId: String
    let readSeq: Int
    let unread: Int
}

/// Body of POST /agents/:id/read.
struct ThreadReadRequest: Encodable, Sendable {
    let seq: Int
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

/// A file sent with a message: its bytes as base64, no data-URL prefix.
struct OutboundAttachment: Encodable, Sendable {
    let mediaType: String
    let data: String
    let filename: String
}

/// Body of POST /router.
struct RouterRequest: Encodable, Sendable {
    let content: String
    var attachments: [OutboundAttachment]?
}

/// Body of POST /messages.
struct MessageRequest: Encodable, Sendable {
    let toAgentId: String
    let content: String
    var attachments: [OutboundAttachment]?
}

/// An agent's two lanes: process is it reading what arrived and answering
/// it, work is it doing the job in the background.
enum Lane: String, Decodable, Sendable, Hashable {
    case process
    case work
}

/// One event from Hath's GET /events stream. Event types this app does not act
/// on yet decode as `unhandled` so the stream keeps going.
enum HathEvent: Decodable, Sendable, Equatable {
    /// A message entered a human thread.
    case message(agentId: String, message: DurableMessage)
    case laneStarted(agentId: String, lane: Lane)
    case laneFinished(agentId: String, lane: Lane)
    case laneFailed(agentId: String, lane: Lane, message: String)
    case routerStarted
    case routerFinished
    case routerFailed(message: String)
    /// Ankur read an agent's thread through `readSeq`, on this device or another.
    case threadRead(agentId: String, readSeq: Int, unread: Int)
    case unhandled(type: String)

    private enum Keys: String, CodingKey {
        case type, agentId, fromAgentId, toAgentId, content, attachments, seq, kind, at, message, lane, readSeq, unread
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
            self = .laneStarted(agentId: try c.decode(String.self, forKey: .agentId), lane: try c.decode(Lane.self, forKey: .lane))
        case "lane_finished":
            self = .laneFinished(agentId: try c.decode(String.self, forKey: .agentId), lane: try c.decode(Lane.self, forKey: .lane))
        case "lane_failed":
            self = .laneFailed(
                agentId: try c.decode(String.self, forKey: .agentId),
                lane: try c.decode(Lane.self, forKey: .lane),
                message: try c.decode(String.self, forKey: .message)
            )
        case "router_started":
            self = .routerStarted
        case "router_finished":
            self = .routerFinished
        case "router_failed":
            self = .routerFailed(message: try c.decode(String.self, forKey: .message))
        case "thread_read":
            self = .threadRead(
                agentId: try c.decode(String.self, forKey: .agentId),
                readSeq: try c.decode(Int.self, forKey: .readSeq),
                unread: try c.decode(Int.self, forKey: .unread)
            )
        default:
            self = .unhandled(type: type)
        }
    }
}

/// One agent from GET /agents: the flat roster, each naming the agent that
/// made it.
struct AgentRecord: Decodable, Sendable, Hashable, Identifiable {
    /// Which of an agent's lanes are running: work, process, or both.
    struct Running: Decodable, Sendable, Hashable {
        /// What the work lane waits on and since when.
        struct Waiting: Decodable, Sendable, Hashable {
            let targets: [String]
            let since: Date
            let wakesBy: Date
        }

        /// Where the agent's work stands, rendered by Hath with no model call. Its times are
        /// ISO strings without fractions, which the shared date decoder does not read, so they
        /// stay text and `AgentStatusView` formats them.
        struct Status: Decodable, Sendable, Hashable {
            struct Job: Decodable, Sendable, Hashable {
                /// The agent that gave the job; nil for Ankur.
                let from: String?
                let at: String
                let content: String
            }

            struct Work: Decodable, Sendable, Hashable {
                enum State: String, Decodable, Sendable, Hashable {
                    case running, waiting, idle
                }

                let state: State
                /// When it began waiting, or its last step while running; nil while idle.
                let since: String?
                let waitingOn: [String]
            }

            /// One of the work lane's last tool calls; `ok` is nil while it has no result.
            struct Call: Decodable, Sendable, Hashable {
                let name: String
                let arg: String
                let ok: Bool?
            }

            /// A helper task in flight.
            struct InFlight: Decodable, Sendable, Hashable {
                let id: String
                let status: String
                let current: String
            }

            /// A message work queued that the process lane has not sent.
            struct Pending: Decodable, Sendable, Hashable {
                let id: Int
                /// The recipient; nil for Ankur.
                let to: String?
                let expectsReply: Bool
                let preview: String
            }

            let job: Job?
            let work: Work
            /// The work lane's last tool call with a short argument; nil before it has acted.
            let step: String?
            /// The last five tool calls, oldest first.
            let recent: [Call]
            let tasks: [InFlight]
            /// Why Nas could not be read for the tasks; nil when it could.
            let tasksUnreadable: String?
            let pending: [Pending]
        }

        let work: Bool
        let process: Bool
        let waitingOn: Waiting?
        /// Nil when no lane runs and work is not waiting.
        let status: Status?
    }

    /// The browser and terminal tasks an agent owns or last steered, most recently active first.
    struct Sessions: Decodable, Sendable, Hashable {
        struct Task: Decodable, Sendable, Hashable {
            /// The task's address, such as `task/browser/3`.
            let id: String
        }

        let tasks: [Task]
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

    var isRunning: Bool { running.work || running.process }

    /// The lanes running now.
    var lanes: Set<Lane> {
        Set([running.process ? Lane.process : nil, running.work ? Lane.work : nil].compactMap { $0 })
    }
}
