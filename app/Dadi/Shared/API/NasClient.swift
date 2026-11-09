import Foundation

/// Nas, the box itself: health, the devices on dadi, and its logs.
struct NasClient: Sendable {
    /// Nas's address on dadi, served by Caddy on the box.
    static let baseURL = URL(string: "http://nas.dadi")!

    let client: ServiceClient

    init(session: URLSession) {
        client = ServiceClient(session: session, baseURL: Self.baseURL)
    }

    /// GET /events: one element per change to the helper tasks, terminals and browsers.
    func changes() async throws -> AsyncThrowingStream<Void, Error> {
        try await client.changes("/events")
    }

    /// GET /status.
    func status() async throws -> NasStatus {
        try await client.get("/status")
    }

    /// GET /clients: every device on dadi, and setup codes not yet used.
    func devices() async throws -> [NasClientDevice] {
        struct Response: Decodable { let clients: [NasClientDevice] }
        let response: Response = try await client.get("/clients")
        return response.clients
    }

    /// GET /logs at `level`, newest first.
    func logs(level: String, limit: Int) async throws -> [NasLogEntry] {
        struct Response: Decodable { let entries: [NasLogEntry] }
        let response: Response = try await client.get("/logs", query: [URLQueryItem(name: "level", value: level), URLQueryItem(name: "limit", value: String(limit))])
        return response.entries
    }

    /// GET /tasks: every browser and terminal helper task.
    func tasks() async throws -> [NasTask] {
        try await client.get("/tasks")
    }

    /// POST /tasks/:kind/:id/pause: holds an awake task, so its helper stops at the next step; pausing a paused task changes nothing.
    func pause(_ task: NasTask) async throws -> NasTask {
        struct Body: Encodable {}
        return try await client.post("/tasks/\(task.route)/pause", body: Body())
    }

    /// POST /tasks/:kind/:id/resume: hands a paused task back to its helper, with `note` when there is one.
    func resume(_ task: NasTask, note: String?) async throws -> NasTask {
        struct Body: Encodable { let note: String? }
        return try await client.post("/tasks/\(task.route)/resume", body: Body(note: note))
    }

    /// POST /tasks/:kind/:id/stop: ends a paused task and tells its agent.
    func stop(_ task: NasTask) async throws -> NasTask {
        struct Body: Encodable {}
        return try await client.post("/tasks/\(task.route)/stop", body: Body())
    }

    private static func escaped(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    }

    /// GET /terminals/:id/capture: the last `lines` lines of the terminal's pane as plain text.
    func terminalCapture(_ id: String, lines: Int) async throws -> String {
        struct Response: Decodable { let output: String }
        let response: Response = try await client.get("/terminals/\(Self.escaped(id))/capture", query: [URLQueryItem(name: "lines", value: String(lines))])
        return response.output
    }

    /// The stream may go this many seconds without a byte: the first frame
    /// waits on the encoder starting, and a still page sends little after.
    static let streamIdle: TimeInterval = 15

    /// GET /browsers/:id/stream: the browser's display as raw H.264 (Annex B).
    func browserStream(_ id: Int, profile: StreamProfile) async throws -> URLSession.AsyncBytes {
        try await client.bytes("/browsers/\(id)/stream", query: [
            URLQueryItem(name: "fps", value: String(profile.fps)),
            URLQueryItem(name: "width", value: String(profile.width)),
            URLQueryItem(name: "kbps", value: String(profile.kbps)),
        ], idle: Self.streamIdle)
    }
}

/// How a view wants a browser's stream.
struct StreamProfile: Sendable, Hashable {
    let fps: Int
    let width: Int
    let kbps: Int

    /// Nas's watch-only defaults, cheap enough to leave open on every pin.
    static let watch = StreamProfile(fps: 5, width: 960, kbps: 600)}
