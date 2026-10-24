import Foundation

/// Hath, dadi's agent runtime: threads, messages, the router and live events.
/// Paths live here; callers pass only domain values.
struct HathClient: Sendable {
    /// Hath's address on dadi, served by Caddy on the box. Fixed by the mesh's
    /// DNS records, not configuration.
    static let baseURL = URL(string: "http://hath.dadi")!

    /// The router runs every agent it hands work to before answering.
    static let routerTimeout: TimeInterval = 300

    /// An agent's wake logs can run to megabytes.
    static let logsTimeout: TimeInterval = 120

    /// A large attachment can take a while to come over the mesh.
    static let attachmentTimeout: TimeInterval = 120

    let client: ServiceClient

    init(session: URLSession) {
        client = ServiceClient(session: session, baseURL: Self.baseURL)
    }

    /// GET /health, given up after `timeout` seconds.
    func health(timeout: TimeInterval) async throws -> HathHealth {
        try await client.get("/health", timeout: timeout)
    }

    /// GET /threads: every human↔agent conversation.
    func threads() async throws -> [ThreadSummary] {
        struct Response: Decodable { let threads: [ThreadSummary] }
        let response: Response = try await client.get("/threads")
        return response.threads
    }

    /// GET /agents/:id/messages: a thread's history, oldest first.
    func messages(agentId: String) async throws -> [DurableMessage] {
        struct Response: Decodable { let messages: [DurableMessage] }
        let response: Response = try await client.get("/agents/\(agentId)/messages")
        return response.messages
    }

    /// GET /attachments/:id: an attachment's bytes.
    func attachment(_ id: String) async throws -> Data {
        try await client.data("/attachments/\(id)", timeout: Self.attachmentTimeout)
    }

    /// GET /agents: every agent, active and retired, each with its parent.
    func agents() async throws -> [AgentRecord] {
        struct Response: Decodable { let agents: [AgentRecord] }
        let response: Response = try await client.get("/agents")
        return response.agents
    }

    /// GET /agents/:id: one agent with the tools it is granted.
    func agent(_ id: String) async throws -> AgentDetail {
        try await client.get("/agents/\(id)")
    }

    /// GET /agents/:id/logs: every row of the agent's newest `wakes` wakes,
    /// newest first.
    func logs(agentId: String, wakes: Int) async throws -> [LogRecord] {
        struct Response: Decodable { let logs: [LogRecord] }
        let response: Response = try await client.get("/agents/\(agentId)/logs", query: [URLQueryItem(name: "wakes", value: String(wakes))], timeout: Self.logsTimeout, decoder: ServiceJSON.verbatim)
        return response.logs
    }

    /// GET /agents/:id/schedules: what the agent sends or receives, next run first.
    func schedules(agentId: String) async throws -> [ScheduledMessage] {
        struct Response: Decodable { let schedules: [ScheduledMessage] }
        let response: Response = try await client.get("/agents/\(agentId)/schedules")
        return response.schedules
    }

    /// PATCH /schedules/:id: change a schedule's time, repeat or message.
    func patchSchedule(_ id: String, _ change: PatchScheduleRequest) async throws -> ScheduledMessage {
        try await client.patch("/schedules/\(id)", body: change)
    }

    /// DELETE /schedules/:id: cancel a schedule.
    func cancelSchedule(_ id: String) async throws {
        try await client.delete("/schedules/\(id)")
    }

    /// POST /agents/:id/read: Ankur has read `agentId`'s thread through `seq`.
    func markRead(_ agentId: String, through seq: Int) async throws -> ThreadRead {
        try await client.post("/agents/\(agentId)/read", body: ThreadReadRequest(seq: seq))
    }

    /// POST /router: hand words to the router, which sends them on as Ankur.
    func route(_ content: String, attachments: [OutboundAttachment] = []) async throws -> PostRouterResponse {
        try await client.post("/router", body: RouterRequest(content: content, attachments: attachments.isEmpty ? nil : attachments), timeout: Self.routerTimeout)
    }

    /// POST /messages: send a message to an agent as Ankur.
    func send(_ content: String, to agentId: String, attachments: [OutboundAttachment] = []) async throws -> PostMessageResponse {
        try await client.post("/messages", body: MessageRequest(toAgentId: agentId, content: content, attachments: attachments.isEmpty ? nil : attachments), timeout: Self.attachmentTimeout)
    }

    /// Hath pings its event stream every 20 s, so this long without a byte
    /// means the connection is gone.
    static let eventsIdle: TimeInterval = 45

    /// GET /events: Hath's live events until the stream ends or goes quiet.
    func events() async throws -> AsyncThrowingStream<HathEvent, Error> {
        Self.events(from: try await client.lines("/events", idle: Self.eventsIdle))
    }

    /// Parses Server-Sent Events lines into events. Comments and blank lines are
    /// skipped; a `data:` payload that does not decode ends the stream with its
    /// error.
    static func events<Lines: AsyncSequence & Sendable>(from lines: Lines) -> AsyncThrowingStream<HathEvent, Error> where Lines.Element == String {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        let event = try ServiceJSON.decoder.decode(HathEvent.self, from: Data(payload.utf8))
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
