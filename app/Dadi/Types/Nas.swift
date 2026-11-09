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
