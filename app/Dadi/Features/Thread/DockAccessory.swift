import SwiftUI

/// What the tab bar's bottom accessory shows.
enum DockPresentation: Equatable {
    /// Talk to Dadi's bar.
    case dadi
    /// Nothing: an open thread carries its own composer in its page.
    case none

    /// The presentation for `page`.
    static func of(page: HomeView.Page) -> DockPresentation {
        switch page {
        case .thread: .none
        case .dadi, .planner, .ghar, .chaavi, .system: .dadi
        }
    }

    /// Whether the tab bar's accessory is shown.
    var showsAccessory: Bool { self == .dadi }
}

/// What the tab bar's bottom accessory holds: Talk to Dadi's bar on every page but an open thread.
struct DockAccessory: View {
    let presentation: DockPresentation
    let router: RouterDock
    /// True while any router run is in flight.
    let active: Bool
    /// False while dadi is out of reach.
    let online: Bool

    var body: some View {
        if presentation == .dadi {
            RouterDockBar(dock: router, active: active, online: online)
        }
    }
}
