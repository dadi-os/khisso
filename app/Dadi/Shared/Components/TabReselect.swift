import SwiftUI
import UIKit

/// The dock's one re-select mechanism: tapping the tab that is already selected. Home handles it for every tab the same
/// way: a page in a sub-state goes back to its root first, and only a page already at its root scrolls to the top.
/// Pages that keep their own state (the Planner) read `tick` and `tab` and reset themselves.
@Observable
@MainActor
final class TabReselect {
    /// Bumped on every re-select.
    private(set) var tick = 0
    /// The tab that was re-selected last.
    private(set) var tab: HomeView.Tab?

    /// Records a re-select of `tab`.
    func fire(_ tab: HomeView.Tab) {
        self.tab = tab
        tick += 1
    }

    /// The root page a re-select of `page`'s tab goes back to, or nil when `page` already is its tab's root.
    static func root(for page: HomeView.Page) -> HomeView.Page? {
        page == page.tab.home ? nil : page.tab.home
    }

    /// What a re-select does to a tab's page, the same rule for every tab: a sub-state goes back to its root.
    enum Reset: Equatable {
        /// Chats: the open thread goes back to the list.
        case chatsList
        /// Chaavi: the folder or kind goes back to Everything.
        case chaaviEverything
        /// Ghar: the tag goes back to everywhere.
        case gharEverywhere
        /// System: the focused section goes back to the overview.
        case systemOverview
        /// The page resets itself from `tick` (the Planner), or is already at its root.
        case none
    }

    /// The reset a re-select of `tab` asks for, given the page open and whether the tab's own state is in a sub-state.
    static func reset(tab: HomeView.Tab, page: HomeView.Page, inSubState: Bool) -> Reset {
        switch tab {
        case .dadi: root(for: page) == nil ? .none : .chatsList
        case .chaavi: inSubState ? .chaaviEverything : .none
        case .ghar: inSubState ? .gharEverywhere : .none
        case .system: inSubState ? .systemOverview : .none
        case .planner: .none
        }
    }

    /// The dock's tabs, left to right.
    static let order: [HomeView.Tab] = [.dadi, .planner, .ghar, .chaavi, .system]
}

/// Watches the tab bar for a tap on the tab that is already selected, which SwiftUI's TabView does not report, and calls
/// `reselected` with it. The tap is observed, not taken: the tab bar behaves as it does without it.
struct TabReselectProbe: UIViewControllerRepresentable {
    let reselected: (HomeView.Tab) -> Void

    func makeUIViewController(context: Context) -> Probe { Probe(reselected: reselected) }

    func updateUIViewController(_ controller: Probe, context: Context) { controller.reselected = reselected }

    final class Probe: UIViewController, UIGestureRecognizerDelegate {
        var reselected: (HomeView.Tab) -> Void
        private weak var attached: UITabBar?

        init(reselected: @escaping (HomeView.Tab) -> Void) {
            self.reselected = reselected
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard attached == nil, let bar = tabBarController?.tabBar ?? Self.findTabBar(in: view.window?.rootViewController) else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            bar.addGestureRecognizer(tap)
            attached = bar
        }

        private static func findTabBar(in controller: UIViewController?) -> UITabBar? {
            guard let controller else { return nil }
            if let bar = (controller as? UITabBarController)?.tabBar { return bar }
            for child in controller.children { if let bar = findTabBar(in: child) { return bar } }
            return findTabBar(in: controller.presentedViewController)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc private func tapped(_ tap: UITapGestureRecognizer) {
            guard let bar = attached, let controller = bar.window?.rootViewController.flatMap(Self.tabController), TabReselect.order.count == (bar.items?.count ?? 0) else { return }
            let index = min(TabReselect.order.count - 1, max(0, Int(tap.location(in: bar).x / (bar.bounds.width / CGFloat(TabReselect.order.count)))))
            guard index == controller.selectedIndex else { return }
            reselected(TabReselect.order[index])
        }

        private static func tabController(_ controller: UIViewController) -> UITabBarController? {
            if let tabs = controller as? UITabBarController { return tabs }
            for child in controller.children { if let tabs = tabController(child) { return tabs } }
            return nil
        }
    }
}
