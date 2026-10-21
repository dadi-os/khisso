import Foundation

/// What the iPhone tells the watch: today's plan, the latest threads and the
/// box's health, small enough to send whole and keep on the watch.
struct WatchSnapshot: Codable, Sendable, Equatable {
    /// One planner block today.
    struct Block: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        /// The SF Symbol for its glyph.
        let symbol: String
        let startAt: Date
        let endAt: Date
        let done: Bool
    }

    /// One agent thread with its agent's lanes.
    struct Thread: Codable, Sendable, Hashable, Identifiable {
        let agentId: String
        let name: String
        /// The agent's latest message, or Ankur's when he spoke last.
        let lastMessage: String
        let lastAt: Date
        let fromUser: Bool
        let thinking: Bool
        let working: Bool

        var id: String { agentId }
    }

    /// The box's modules: all healthy, or the ones down.
    struct Box: Codable, Sendable, Equatable {
        let down: [String]
    }

    let at: Date
    let today: [Block]
    let threads: [Thread]
    let box: Box
}

/// The watch's requests and the iPhone's answers over WatchConnectivity, as
/// property-list dictionaries keyed by these names.
enum WatchLink {
    /// The key naming what a message is.
    static let op = "op"
    static let snapshot = "snapshot"
    static let text = "text"
    static let agentId = "agentId"
    static let name = "name"
    static let error = "error"

    /// Watch to iPhone: send a fresh snapshot.
    static let refresh = "refresh"
    /// Watch to iPhone: hand `text` to the router.
    static let route = "route"
    /// Watch to iPhone: send `text` to `agentId`.
    static let reply = "reply"
    /// iPhone to watch: the router sent the words to `agentId`, named `name`, or failed with `error`.
    static let routed = "routed"

    /// How many threads the watch shows.
    static let threadLimit = 8
    /// The most of a message the watch keeps.
    static let messageLimit = 600

    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
}
