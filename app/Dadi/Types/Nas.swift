import Foundation

/// GET /status: the box's health at a glance.
struct NasStatus: Decodable, Sendable, Hashable {
    /// A module and whether its health check passes.
    struct Service: Decodable, Sendable, Hashable {
        let name: String
        let healthy: Bool
    }

    /// One physical drive with a mounted filesystem.
    struct Disk: Decodable, Sendable, Hashable {
        let name: String
        let model: String?
        let mount: String
        let freeBytes: Int64
        let totalBytes: Int64
        let usedPercent: Double
    }

    /// How full the system disk is.
    struct Usage: Decodable, Sendable, Hashable {
        let freeBytes: Int64
        let totalBytes: Int64
        let usedPercent: Double
    }

    /// A processor or memory meter.
    struct Meter: Decodable, Sendable, Hashable {
        let name: String
        let usedPercent: Double
    }

    let uptimeSeconds: Int
    let services: [Service]
    let disk: Usage
    let disks: [Disk]
    let cpu: Meter
    let memory: Meter
}

/// A device on dadi from GET /clients.
struct NasClientDevice: Decodable, Sendable, Hashable, Identifiable {
    let nodeName: String
    let online: Bool
    /// A setup code was made for it but it has not joined yet.
    let pending: Bool
    let ipAddresses: [String]

    var id: String { nodeName }
}

/// A log line from GET /logs.
struct NasLogEntry: Decodable, Sendable, Hashable {
    let time: Date
    let service: String
    let level: String
    let msg: String
    let code: String?
    /// The original JSON line, with fields like the agent's message.
    let raw: String

    /// What failed, in words: a request line reads "POST /command failed with 500" from its method, path and status;
    /// any other line is its own message.
    var title: String {
        guard let method = fields["method"] as? String, let path = fields["path"] as? String else { return msg }
        let status = (fields["status"] as? Int).map { " with \($0)" } ?? ""
        return "\(method) \(path) failed\(status)"
    }

    /// The line's own error text and the agent it concerns, when it carries them.
    var detail: String? {
        let parts = [fields["error"] as? String ?? fields["err"] as? String, (fields["agent"] ?? fields["agent_id"]) as? String]
        let shown = parts.compactMap { $0 }.filter { !$0.isEmpty }
        return shown.isEmpty ? nil : shown.joined(separator: " · ")
    }

    private var fields: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
    }
}

/// Identical recent errors folded into one row with how many times they happened.
struct NasLogGroup: Hashable, Identifiable {
    /// The newest occurrence.
    let entry: NasLogEntry
    let count: Int

    var id: String { "\(entry.service)|\(entry.code ?? "")|\(entry.title)|\(entry.detail ?? "")" }

    /// Groups `entries` (newest first) by module, code, title and detail, keeping the order of first appearance.
    static func grouped(_ entries: [NasLogEntry]) -> [NasLogGroup] {
        var order: [String] = []
        var found: [String: NasLogGroup] = [:]
        for entry in entries {
            let key = NasLogGroup(entry: entry, count: 1)
            if let known = found[key.id] {
                found[key.id] = NasLogGroup(entry: known.entry, count: known.count + 1)
            } else {
                order.append(key.id)
                found[key.id] = key
            }
        }
        return order.compactMap { found[$0] }
    }
}

/// A browser or terminal helper task, from GET /tasks.
struct NasTask: Decodable, Sendable, Hashable, Identifiable {
    /// The task's address, such as `task/browser/3`.
    let task: String
    let kind: String
    /// The agent that owns it.
    let owner: String
    let purpose: String
    /// working, paused (held by Ankur), idle, asking (it asked its agent), asleep or stopped (halted by Ankur or Hath).
    let status: String
    /// The browser slot or terminal id it holds; nil while it sleeps.
    let resource: String?
    /// The helper's state summary: its current step, or what it was doing when it slept.
    let state: String
    let lastActivity: Date
    /// The address of the page in front, for a browser task whose browser is awake.
    let activeUrl: String?

    var id: String { task }

    /// The path under `/tasks` that addresses this task: `browser/3f2a91` for `task/browser/3f2a91`.
    var route: String { task.replacingOccurrences(of: "task/", with: "", options: .anchored) }

    /// True while it holds a browser or terminal that can be watched.
    var live: Bool { resource != nil && status != "asleep" && status != "stopped" }

    /// True while Hath can still halt it: it is working, paused, idle or asking.
    var stoppable: Bool { ["working", "paused", "idle", "asking"].contains(status) }
}

/// One file, folder or symlink in the dadi home, from GET /fs/stat and GET /fs/list.
struct NasFileEntry: Decodable, Sendable, Hashable, Identifiable {
    enum Kind: String, Decodable, Sendable {
        case file, folder, symlink
    }

    let name: String
    /// Absolute on the box, as in a `box://` link.
    let path: String
    let kind: Kind
    let size: Int64
    let modified: Date
    /// By extension; empty for a folder, a symlink and an unknown extension.
    let mediaType: String

    var id: String { path }

    private enum CodingKeys: String, CodingKey {
        case name, path, kind, size, modified, mediaType
    }

    /// Nas writes `modified` as RFC 3339 with or without fractional seconds.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        kind = try c.decode(Kind.self, forKey: .kind)
        size = try c.decode(Int64.self, forKey: .size)
        modified = try c.decodeInstant(forKey: .modified)
        mediaType = try c.decode(String.self, forKey: .mediaType)
    }
}

/// GET /fs/list: a folder's entries, folders first and then by name.
struct NasFileList: Decodable, Sendable {
    let path: String
    let entries: [NasFileEntry]
}

/// POST /fs/upload: where the file landed, which differs from the name sent when that name was taken.
struct NasUploaded: Decodable, Sendable, Hashable {
    let path: String
    let name: String
    let size: Int64
}
