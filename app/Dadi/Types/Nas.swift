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
    /// working, paused (Ankur has taken it over), idle, asking (it asked its agent), asleep or stopped (halted by Ankur or Hath).
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

    /// True while Ankur can act on its browser or terminal.
    var drivable: Bool { resource != nil && status != "asleep" && status != "stopped" }

    /// True while Hath can still halt it: it is working, paused, idle or asking.
    var stoppable: Bool { ["working", "paused", "idle", "asking"].contains(status) }
}

/// One pointer or key event Ankur sends into a browser, as POST /browsers/:id/input takes it.
/// Positions are fractions (0 to 1) of the display.
struct BrowserInputEvent: Encodable, Sendable {
    /// move, down, up, wheel, key_down or key_up.
    let type: String
    var x = 0.0
    var y = 0.0
    var button = "none"
    var buttons = 0
    var clickCount = 0
    var deltaX = 0.0
    var deltaY = 0.0
    var key = ""
    var code = ""
    var keyCode = 0
    var text = ""

    /// A left press or release at a fraction of the display.
    static func pointer(_ type: String, x: Double, y: Double) -> BrowserInputEvent {
        BrowserInputEvent(type: type, x: x, y: y, button: "left", buttons: type == "up" ? 0 : 1, clickCount: type == "move" ? 0 : 1)
    }

    /// A wheel turn at a fraction of the display, `deltaX` and `deltaY` in the page's pixels (positive scrolls right and down).
    static func wheel(x: Double, y: Double, deltaX: Double, deltaY: Double) -> BrowserInputEvent {
        BrowserInputEvent(type: "wheel", x: x, y: y, deltaX: deltaX, deltaY: deltaY)
    }

    /// A key press and release for `key`, typing `text` when it types a character.
    static func press(key: String, code: String, keyCode: Int, text: String = "") -> [BrowserInputEvent] {
        [
            BrowserInputEvent(type: "key_down", key: key, code: code, keyCode: keyCode, text: text),
            BrowserInputEvent(type: "key_up", key: key, code: code, keyCode: keyCode),
        ]
    }
}
