import Foundation

/// How the Chats tab's navigation stack and Home's page agree: a thread is one agent id pushed on the list.
enum ChatsRoute {
    /// The stack for `page`: the open thread's agent, or nothing for the list.
    static func path(for page: HomeView.Page) -> [String] {
        if case .thread(let agentId) = page { [agentId] } else { [] }
    }

    /// The Chats page a stack shows: its top thread, or the list.
    static func page(for path: [String]) -> HomeView.Page {
        path.last.map(HomeView.Page.thread) ?? .dadi
    }
}
