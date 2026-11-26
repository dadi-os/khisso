import SwiftUI

/// The thread the dock's accessory writes to.
struct DockThread {
    let name: String
    let draft: ThreadDraft
    /// Sends the draft to the agent.
    let send: () -> Void
}

/// What the tab bar's bottom accessory shows, and whether the thread's composer is above the keyboard.
enum DockPresentation: Equatable {
    /// Talk to Dadi's bar.
    case dadi
    /// A thread's composer in the accessory.
    case threadAccessory
    /// A thread's composer above the keyboard, the accessory away.
    case keyboardBar
    /// Nothing: reserved for a page that carries no composer.
    case none

    /// The presentation for `page`, while a thread's field is being typed in or not.
    static func of(page: HomeView.Page, editing: Bool) -> DockPresentation {
        switch page {
        case .dadi: .dadi
        case .thread: editing ? .keyboardBar : .threadAccessory
        case .planner, .ghar, .chaavi, .system: .dadi
        }
    }

    /// Whether the tab bar's accessory is shown.
    var showsAccessory: Bool { self == .dadi || self == .threadAccessory }
}

/// What the tab bar's bottom accessory holds: Talk to Dadi's bar on every page but Chats, and in an
/// open thread that thread's composer, which moves above the keyboard while it is typed in.
struct DockAccessory: View {
    let presentation: DockPresentation
    let router: RouterDock
    /// True while any router run is in flight.
    let active: Bool
    /// False while dadi is out of reach.
    let online: Bool
    /// The open thread, or nil on every other page.
    let thread: DockThread?

    var body: some View {
        switch presentation {
        case .dadi:
            RouterDockBar(dock: router, active: active, online: online)
        case .threadAccessory:
            if let thread {
                ThreadComposerBar(name: thread.name, draft: thread.draft, placement: .accessory, send: thread.send)
            }
        case .keyboardBar, .none:
            EmptyView()
        }
    }
}
