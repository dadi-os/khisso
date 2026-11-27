import Foundation

/// Nas, the box itself: health, the devices on dadi, its logs, and the files in the dadi home.
struct NasClient: Sendable {
    /// Nas's address on dadi, served by Caddy on the box.
    static let baseURL = URL(string: "http://nas.dadi")!

    let client: ServiceClient

    init(session: URLSession) {
        client = ServiceClient(session: session, baseURL: Self.baseURL)
    }

    /// A file's bytes can take a while over the mesh.
    static let fileTimeout: TimeInterval = 120

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

    /// GET /fs/stat: one entry. A path that is gone is a `not_found` error (404), which is how a removed file is told.
    func stat(_ path: String) async throws -> NasFileEntry {
        try await client.get("/fs/stat", query: [URLQueryItem(name: "path", value: path)])
    }

    /// GET /fs/list: a folder's entries, folders first and then by name, without dotfiles.
    func list(_ path: String) async throws -> NasFileList {
        try await client.get("/fs/list", query: [URLQueryItem(name: "path", value: path)])
    }

    /// GET /fs/raw: the file's bytes, saved under its own name in a temporary folder for the caller to use and remove.
    func download(_ entry: NasFileEntry) async throws -> URL {
        try await client.download("/fs/raw", query: [URLQueryItem(name: "path", value: entry.path)], filename: entry.name, timeout: Self.fileTimeout)
    }

    /// POST /fs/upload: puts the file at `file` in `folder` (created when missing) under `name`. A taken name gets
    /// " (2)", so the answer's path is where it landed, and a link is built from that.
    func upload(_ file: URL, named name: String, mediaType: String, to folder: String) async throws -> NasUploaded {
        try await client.upload("/fs/upload", fields: [(name: "path", value: folder)], file: file, filename: name, mediaType: mediaType, timeout: Self.fileTimeout)
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
