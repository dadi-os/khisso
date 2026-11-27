import SwiftUI

/// What the tab bar's bottom accessory shows.
enum DockPresentation: Equatable {
    /// Talk to Dadi's bar.
    case dadi
    /// The open thread's message bar, which the system lowers beside the minimized tab bar.
    case thread(String)

    /// The presentation for `page`.
    static func of(page: HomeView.Page) -> DockPresentation {
        switch page {
        case .thread(let agentId): .thread(agentId)
        case .dadi, .planner, .ghar, .chaavi, .system: .dadi
        }
    }
}

/// What the accessory shows for an open thread: whom it is for and what the draft holds.
struct ThreadAccessory {
    let name: String
    let draft: ThreadDraft
}

/// What the tab bar's bottom accessory holds: Talk to Dadi's bar, or the open thread's message bar. The system places it
/// above the tab bar and beside the single icon when the bar minimizes, and animates the move itself. The thread's own
/// composer, which rides the keyboard, opens from it.
struct DockAccessory: View {
    let presentation: DockPresentation
    let router: RouterDock
    /// True while any router run is in flight.
    let active: Bool
    /// False while dadi is out of reach.
    let online: Bool
    /// The open thread's bar; nil on every other page.
    let thread: ThreadAccessory?

    var body: some View {
        switch presentation {
        case .dadi:
            RouterDockBar(dock: router, active: active, online: online)
        case .thread(let agentId):
            if let thread {
                ThreadDockBar(name: thread.name, draft: thread.draft)
                    .id(agentId)
            }
        }
    }
}

/// The thread's bar in the dock: what is drafted, or the prompt, opening the composer over the keyboard when tapped.
struct ThreadDockBar: View {
    let name: String
    let draft: ThreadDraft

    var body: some View {
        Button { draft.focusing = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.inkMuted)
                Text(draft.text.isEmpty ? "Message \(name)\u{2026}" : draft.text)
                    .font(.body)
                    .foregroundStyle(draft.text.isEmpty ? Color.inkMuted : .ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .frostedBacking(.capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Message \(name)")
        .accessibilityHint("Opens the message field")
    }
}
