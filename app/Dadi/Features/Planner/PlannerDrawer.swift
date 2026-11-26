import SwiftUI

/// The Planner's drawer: today's widget, then the two things the page can show, Timeline and Checklist, and under
/// them the timeline's three views.
struct PlannerDrawer: View {
    let yaad: YaadClient
    let route: PlannerRoute
    /// False while dadi is out of reach.
    let online: Bool
    /// Shows `route` and closes the drawer.
    let choose: (PlannerRoute) -> Void

    @State private var actions: PlannerActions

    /// - Parameters:
    ///   - message: opens the thread of the agent with this id, with the text ready in its composer when given.
    ///   - reachable: whether an agent is still running.
    ///   - nameOf: an agent's name for display.
    init(yaad: YaadClient, route: PlannerRoute, online: Bool, message: @escaping (String, String?) -> Void, reachable: @escaping (String) -> Bool, nameOf: @escaping (String) -> String, choose: @escaping (PlannerRoute) -> Void) {
        self.yaad = yaad
        self.route = route
        self.online = online
        self.choose = choose
        _actions = State(initialValue: PlannerActions(yaad: yaad, message: message, reachable: reachable, nameOf: nameOf))
    }

    /// `route` after Ankur picks `section`: Timeline keeps its view, Checklist replaces the page.
    static func picking(_ section: PlannerSection, from route: PlannerRoute) -> PlannerRoute {
        var next = route
        switch section {
        case .timeline: next.section = .timeline
        case .checklist: next.showChecklist()
        }
        return next
    }

    /// `route` after Ankur picks a timeline view.
    static func picking(_ mode: PlannerMode, from route: PlannerRoute) -> PlannerRoute {
        var next = route
        next.show(mode)
        return next
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PlannerWidget(yaad: yaad, actions: actions, online: online) { choose(Self.picking(.day, from: route)) }
                .frame(height: 340)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(PlannerSection.allCases, id: \.self) { section in
                    tile(symbol: section.symbol, title: section.rawValue, current: route.section == section) { choose(Self.picking(section, from: route)) }
                }
            }
            if route.section == .timeline {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(PlannerMode.allCases, id: \.self) { mode in
                        tile(symbol: mode.symbol, title: mode.rawValue, current: route.mode == mode) { choose(Self.picking(mode, from: route)) }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .animation(Motion.snap, value: route.section)
        .plannerSheets(actions: actions, yaad: yaad)
    }

    /// A view's tile, filled sage while it is the one shown.
    private func tile(symbol: String, title: String, current: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(current ? Color.bone : .sageDeep)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(current ? Color.bone : .ink)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(current ? AnyShapeStyle(Color.sageDeep) : AnyShapeStyle(Color.boneRaised.opacity(0.92)))
                    .shadow(color: .black.opacity(current ? 0.12 : 0.05), radius: current ? 8 : 4, y: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(current ? Color.clear : Color.sageLine.opacity(0.55), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .animation(Motion.snap, value: current)
    }
}
