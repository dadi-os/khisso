import Foundation

/// The helper tasks a thread pins: the agent's newest live browser and newest live terminal, where live
/// means awake and holding a browser or terminal.
struct PinnedTasks: Equatable {
    let browser: NasTask?
    let terminal: NasTask?

    /// Picks the pins from an agent's tasks, newest activity first.
    init(of tasks: [NasTask]) {
        let live = tasks.filter(\.drivable).sorted { $0.lastActivity > $1.lastActivity }
        browser = live.first { $0.kind == "browser" }
        terminal = live.first { $0.kind == "terminal" }
    }

    var isEmpty: Bool { browser == nil && terminal == nil }

    /// A page address as a preview's address bar shows it: without its scheme and a lone trailing slash.
    static func pageAddress(_ url: String?) -> String {
        (url ?? "")
            .replacingOccurrences(of: "^[a-z][a-z0-9+.-]*://", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "/$", with: "", options: .regularExpression)
    }
}
