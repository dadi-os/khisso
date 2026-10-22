import Foundation

/// Hath, dadi's agent runtime: threads, messages, the router and live events.
/// Paths live here; callers pass only domain values.
struct HathClient: Sendable {
    /// Hath's address on dadi, served by Caddy on the box. Fixed by the mesh's
    /// DNS records, not configuration.
    static let baseURL = URL(string: "http://hath.dadi")!

    /// The router runs every agent it hands work to before answering.
    static let routerTimeout: TimeInterval = 300

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

    /// POST /router: hand words to the router, which sends them on as Ankur.
    func route(_ content: String) async throws -> PostRouterResponse {
        try await client.post("/router", body: RouterRequest(content: content), timeout: Self.routerTimeout)
    }

    /// POST /messages: send a message to an agent as Ankur.
    func send(_ content: String, to agentId: String) async throws -> PostMessageResponse {
        try await client.post("/messages", body: MessageRequest(toAgentId: agentId, content: content))
    }

    /// GET /events: Hath's live events until the stream ends.
    func events() async throws -> AsyncThrowingStream<HathEvent, Error> {
        Self.events(from: try await client.lines("/events"))
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
