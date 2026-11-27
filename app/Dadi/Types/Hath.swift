import Foundation

/// GET /health: Hath's process liveness.
struct HathHealth: Decodable, Sendable {
    let status: String
    /// When this Hath process started; identifies the process, not chat history.
    let startedAt: Date
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

/// What a message is: `notice` is Hath's note to an agent and `utterance` is Ankur's words to the router.
enum MessageKind: String, Decodable, Sendable, Hashable {
    case message
    case notice
    case utterance
}

/// What the sender says a message to the job's requester leaves open: `done` answered it, `blocked` cannot
/// proceed, `needs_input` is parked on Ankur's answer.
enum MessageStatus: String, Decodable, Sendable, Hashable {
    case done
    case blocked
    case needsInput = "needs_input"
}

/// One durable message in a human thread, from GET /agents/:id/messages.
struct DurableMessage: Decodable, Sendable, Hashable, Identifiable {
    /// Hath's ordering of messages; also identifies a message across history and events.
    let seq: Int
    /// Nil when Ankur sent it.
    let fromAgentId: String?
    /// Nil when it was sent to Ankur.
    let toAgentId: String?
    let content: String
    /// Hath's own notes to agents are not part of the thread; a message is `message` or absent.
    let kind: MessageKind?
    /// What the sender says the message leaves open, set on a message to the job's requester. Hath's thread
    /// route and event do not carry it yet, so it is nil there and `Standing` reads it from the wakes.
    let status: MessageStatus?
    let createdAt: Date

    var id: Int { seq }
    var fromUser: Bool { fromAgentId == nil }
}

extension DurableMessage {
    private enum CodingKeys: String, CodingKey {
        case seq, fromAgentId, toAgentId, content, kind, status, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq = try c.decode(Int.self, forKey: .seq)
        fromAgentId = try c.decodeIfPresent(String.self, forKey: .fromAgentId)
        toAgentId = try c.decodeIfPresent(String.self, forKey: .toAgentId)
        content = try c.decode(String.self, forKey: .content)
        kind = try c.decodeIfPresent(MessageKind.self, forKey: .kind)
        status = try c.decodeIfPresent(MessageStatus.self, forKey: .status)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

/// One message the router sent to an agent as Ankur.
struct RoutedMessage: Decodable, Sendable, Hashable {
    let toAgentId: String
    let content: String
    let seq: Int
    let createdAt: Date
}

/// POST /router: every message the router sent, in order; may be empty.
struct PostRouterResponse: Decodable, Sendable {
    let messages: [RoutedMessage]
}

/// GET /router: the router runs in flight, none when it is idle.
struct RouterRuns: Decodable, Sendable {
    struct Run: Decodable, Sendable, Hashable {
        let runId: String
        let at: Date
    }

    let running: [Run]
}

/// POST /messages: the delivered message.
struct PostMessageResponse: Decodable, Sendable {
    let toAgentId: String
    let content: String
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

/// Where a wake stands. `waiting` appears only on an agent's latest wake, when the agent watches a task or agent.
enum WakeOutcome: String, Decodable, Sendable, Hashable {
    case running
    case waiting
    case yielded
    case failed
}

/// What a wake did, counted.
struct WakeCounts: Decodable, Sendable, Hashable {
    static let none = WakeCounts(toolCalls: 0, messagesSent: 0, messagesReceived: 0)

    let toolCalls: Int
    let messagesSent: Int
    let messagesReceived: Int

    private enum CodingKeys: String, CodingKey {
        case toolCalls = "tool_calls"
        case messagesSent = "messages_sent"
        case messagesReceived = "messages_received"
    }
}

extension Date {
    /// A time as Hath writes it: an ISO 8601 instant with or without fractional seconds. The job ledger and
    /// routines carry whole seconds with an offset, the rest of Hath's payloads milliseconds.
    static func hathInstant(_ text: String) -> Date? {
        (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: Date.ISO8601FormatStyle()))
    }
}

extension KeyedDecodingContainer {
    /// The instant at `key`, read with `Date.hathInstant`.
    func decodeInstant(forKey key: Key) throws -> Date {
        let text = try decode(String.self, forKey: key)
        guard let date = Date.hathInstant(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "not an ISO 8601 date: \(text)")
        }
        return date
    }

    /// The instant at `key`, nil when absent or null.
    func decodeInstantIfPresent(forKey key: Key) throws -> Date? {
        try contains(key) && !(try decodeNil(forKey: key)) ? decodeInstant(forKey: key) : nil
    }
}

/// One event from Hath's GET /events stream. Event types this app does not act
/// on yet decode as `unhandled` so the stream keeps going.
enum HathEvent: Decodable, Sendable, Equatable {
    /// A message entered a human thread.
    case message(agentId: String, message: DurableMessage)
    /// A wake began: the agent's loop is working.
    case wakeStarted(agentId: String, wakeId: String)
    /// A running wake did more; `counts` are its totals so far.
    case wakeActivity(agentId: String, wakeId: String, counts: WakeCounts)
    /// A wake ended; the agent is no longer working, and a failed one has a reason in its timeline.
    case wakeEnded(agentId: String, wakeId: String, outcome: WakeOutcome)
    /// A routine or reminder was created, ended, cancelled or fired; the lists read again.
    case schedulesChanged
    /// A router run began; its `runId` ties it to its finish or failure, and runs can overlap.
    case routerStarted(runId: String)
    case routerFinished(runId: String)
    case routerFailed(runId: String, message: String)
    /// Ankur read an agent's thread through `readSeq`, on this device or another.
    case threadRead(agentId: String, readSeq: Int, unread: Int)
    case unhandled(type: String)

    private enum Keys: String, CodingKey {
        case type, agentId, fromAgentId, toAgentId, content, seq, kind, status, at, message, readSeq, unread, runId, wakeId, outcome, counts
    }

    /// The counts as the stream's snake-case decoder hands them over.
    private enum CountKeys: String, CodingKey { case toolCalls, messagesSent, messagesReceived }

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
                kind: try c.decodeIfPresent(MessageKind.self, forKey: .kind),
                status: try c.decodeIfPresent(MessageStatus.self, forKey: .status),
                createdAt: try c.decode(Date.self, forKey: .at)
            ))
        case "wake_started":
            self = .wakeStarted(agentId: try c.decode(String.self, forKey: .agentId), wakeId: try c.decode(String.self, forKey: .wakeId))
        case "wake_activity":
            let counts = try c.nestedContainer(keyedBy: CountKeys.self, forKey: .counts)
            self = .wakeActivity(
                agentId: try c.decode(String.self, forKey: .agentId),
                wakeId: try c.decode(String.self, forKey: .wakeId),
                counts: WakeCounts(
                    toolCalls: try counts.decode(Int.self, forKey: .toolCalls),
                    messagesSent: try counts.decode(Int.self, forKey: .messagesSent),
                    messagesReceived: try counts.decode(Int.self, forKey: .messagesReceived)
                )
            )
        case "wake_ended":
            self = .wakeEnded(agentId: try c.decode(String.self, forKey: .agentId), wakeId: try c.decode(String.self, forKey: .wakeId), outcome: try c.decode(WakeOutcome.self, forKey: .outcome))
        case "schedules_changed":
            self = .schedulesChanged
        case "router_started":
            self = .routerStarted(runId: try c.decode(String.self, forKey: .runId))
        case "router_finished":
            self = .routerFinished(runId: try c.decode(String.self, forKey: .runId))
        case "router_failed":
            self = .routerFailed(runId: try c.decode(String.self, forKey: .runId), message: try c.decode(String.self, forKey: .message))
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
    /// What the agent's one loop is doing: running a step, waiting on a helper or another agent after its
    /// wake ended, or at rest; and the job its current wake is on.
    struct Running: Decodable, Sendable, Hashable {
        /// What the agent waits on and since when.
        struct Waiting: Decodable, Sendable, Hashable {
            let targets: [String]
            let since: Date
            let wakesBy: Date

            private enum CodingKeys: String, CodingKey { case targets, since, wakesBy }

            init(targets: [String], since: Date, wakesBy: Date) {
                self.targets = targets
                self.since = since
                self.wakesBy = wakesBy
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                targets = try c.decode([String].self, forKey: .targets)
                since = try c.decodeInstant(forKey: .since)
                wakesBy = try c.decodeInstant(forKey: .wakesBy)
            }
        }

        /// The agent's loop is running a step now.
        let working: Bool
        let waitingOn: Waiting?
        /// The job of the agent's current wake; nil when it has none.
        let job: JobLedger?

        static let quiet = Running(working: false, waitingOn: nil, job: nil)
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
    var running: Running
    let sessions: Sessions
    let createdAt: Date
    let updatedAt: Date
}

/// One piece of work an agent is on, as its wake sees it (`running.job` on GET /agents): opened by a
/// message, closed when the requester has been told.
struct JobLedger: Decodable, Sendable, Hashable {
    struct Opened: Decodable, Sendable, Hashable {
        let seq: Int
        let at: Date
        /// The opening message, clipped.
        let content: String

        private enum CodingKeys: String, CodingKey { case seq, at, content }

        init(seq: Int, at: Date, content: String) {
            self.seq = seq
            self.at = at
            self.content = content
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            seq = try c.decode(Int.self, forKey: .seq)
            at = try c.decodeInstant(forKey: .at)
            content = try c.decode(String.self, forKey: .content)
        }
    }

    /// An agent it asked, and the seq of that agent's first reply (nil while none).
    struct Ask: Decodable, Sendable, Hashable {
        let to: String
        let seq: Int
        let answeredSeq: Int?
    }

    /// Something it already sent the requester.
    struct Told: Decodable, Sendable, Hashable {
        let seq: Int
        let preview: String
    }

    struct Stopped: Decodable, Sendable, Hashable {
        let at: Date
        /// `ankur` for Ankur's own stop, else the agent id.
        let by: String

        private enum CodingKeys: String, CodingKey { case at, by }

        init(at: Date, by: String) {
            self.at = at
            self.by = by
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            at = try c.decodeInstant(forKey: .at)
            by = try c.decode(String.self, forKey: .by)
        }
    }

    /// The job's number: its opening message's seq.
    let job: Int
    /// Who asked: an agent id, nil for Ankur, the agent's own id for a routine run.
    let requester: String?
    let opened: Opened
    /// When the answer is due; only Ankur's jobs have one.
    let answerBy: Date?
    let asks: [Ask]
    /// The helper tasks steered in the job.
    let helpers: [String]
    /// Titles of what the job stored in memory.
    let stored: [String]
    /// What the agent already sent the requester, oldest first.
    let told: [Told]
    /// When the agent will check back, soonest first.
    let reminders: [Date]
    let stopped: Stopped?

    private enum CodingKeys: String, CodingKey { case job, requester, opened, answerBy, asks, helpers, stored, told, reminders, stopped }

    init(job: Int, requester: String?, opened: Opened, answerBy: Date?, asks: [Ask] = [], helpers: [String] = [], stored: [String] = [], told: [Told] = [], reminders: [Date] = [], stopped: Stopped? = nil) {
        self.job = job
        self.requester = requester
        self.opened = opened
        self.answerBy = answerBy
        self.asks = asks
        self.helpers = helpers
        self.stored = stored
        self.told = told
        self.reminders = reminders
        self.stopped = stopped
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        job = try c.decode(Int.self, forKey: .job)
        requester = try c.decodeIfPresent(String.self, forKey: .requester)
        opened = try c.decode(Opened.self, forKey: .opened)
        answerBy = try c.decodeInstantIfPresent(forKey: .answerBy)
        asks = try c.decode([Ask].self, forKey: .asks)
        helpers = try c.decode([String].self, forKey: .helpers)
        stored = try c.decode([String].self, forKey: .stored)
        told = try c.decode([Told].self, forKey: .told)
        reminders = try c.decode([String].self, forKey: .reminders).map { text in
            guard let date = Date.hathInstant(text) else { throw DecodingError.dataCorruptedError(forKey: .reminders, in: c, debugDescription: "not an ISO 8601 date: \(text)") }
            return date
        }
        stopped = try c.decodeIfPresent(Stopped.self, forKey: .stopped)
    }
}
