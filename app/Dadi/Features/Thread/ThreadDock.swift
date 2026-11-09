import SwiftUI

/// Whether a thread's composer is out or has gone down into the dock. The dock is the system tab bar,
/// which condenses as a page scrolls and puts its bottom accessory beside it; in a thread the
/// accessory then holds a compact "Message" capsule and the Talk to Dadi mark, and the full composer
/// slides down to make room. The tab bar condenses when the thread scrolls up into its history and
/// expands when it scrolls back down, so the composer follows the reader away from the newest message.
@MainActor
@Observable
final class ThreadDock {
    /// True while the tab bar is condensed, set by the accessory from its placement.
    var condensed = false
    /// True while the person asked to write from the condensed dock.
    var writing = false

    /// True when the full composer shows: the tab bar is expanded, or the person is writing.
    var composerShown: Bool { Self.showsComposer(condensed: condensed, writing: writing) }

    /// Whether the full composer shows for the dock's state.
    nonisolated static func showsComposer(condensed: Bool, writing: Bool) -> Bool { !condensed || writing }

    /// Records the tab bar's state; expanding it ends writing from the condensed dock.
    func condense(_ condensed: Bool) {
        self.condensed = condensed
        if !condensed { writing = false }
    }
}

/// What the tab bar's bottom accessory holds: Talk to Dadi's capsule, and in a thread, once the bar is
/// condensed, the thread's compact composer beside the Talk to Dadi mark. It reports its placement to the
/// thread dock whichever page is open.
struct DockAccessory: View {
    let router: RouterDock
    /// True while any router run is in flight.
    let active: Bool
    /// False while dadi is out of reach.
    let online: Bool
    let thread: ThreadDock
    /// The open thread's agent name, or nil when no thread is open.
    let threadName: String?

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        let inline = placement == .inline
        Group {
            if let threadName, inline {
                HStack(spacing: 6) {
                    Button { withAnimation(Motion.snap) { thread.writing = true } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "text.bubble")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.sageDeep)
                            Text("Message \(threadName)\u{2026}")
                                .font(.subheadline)
                                .foregroundStyle(.inkMuted)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Message \(threadName)")
                    Button { router.compose() } label: {
                        RouterMark(active: active)
                            .frame(width: 44, height: 44)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .disabled(!online)
                    .opacity(online ? 1 : 0.6)
                    .accessibilityLabel("Talk to Dadi")
                }
                .transition(.opacity)
            } else {
                RouterDockBar(dock: router, active: active, online: online)
                    .transition(.opacity)
            }
        }
        .animation(Motion.snap, value: inline)
        .onChange(of: inline, initial: true) { _, condensed in thread.condense(condensed) }
    }
}
