import SwiftUI

/// What is on and what is next today, for the drawer's glance.
struct NowNext: Equatable {
    let current: Plan?
    let next: Plan?
}

/// The Planner's drawer: what is on now and next as two quiet lines, the page (Timeline or Checklist), a month to jump
/// to a date (a dot under each day with plans, a Today button) and Someday with its true count. The timeline's Day,
/// Week and Month are chosen in the top bar. Sections are set apart by space, not by cards or headings.
struct PlannerDrawer: View {
    let yaad: YaadClient
    let route: PlannerRoute
    /// False while dadi is out of reach.
    let online: Bool
    /// Shows `route` and closes the drawer.
    let choose: (PlannerRoute) -> Void

    @Environment(LiveData.self) private var live: LiveData?
    @State private var actions: PlannerActions
    @State private var month = MonthPaging.first(of: .now)
    @State private var monthPlans: [Plan] = []
    @State private var todayPlans: [Plan] = []
    @State private var somedayCount: Int?
    @State private var error: String?
    @State private var readAt: Date?

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
        _month = State(initialValue: MonthPaging.first(of: route.day ?? .now))
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

    /// `route` after Ankur picks `day` on the month: the Day view on that day, whatever the page was.
    static func picking(day: Date, from route: PlannerRoute, calendar: Calendar = .current) -> PlannerRoute {
        var next = route
        next.open(day: day, calendar: calendar)
        return next
    }

    /// The day the month marks as chosen: the day the Day view shows; nil on Week, Month and the Checklist.
    static func selectedDay(_ route: PlannerRoute, now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard route.section == .timeline, route.mode == .day else { return nil }
        return calendar.startOfDay(for: route.day ?? now)
    }

    /// The plan that is on and the one that is next today, from the plans Ankur keeps.
    static func nowNext(_ plans: [Plan], now: Date, calendar: Calendar = .current) -> NowNext {
        let kept = PlanFilter.grid(plans).filter { !$0.declined }
        let nextID = PlanTime.nextPlanID(kept, now: now, calendar: calendar)
        return NowNext(current: kept.first { PlanTime.state($0, now: now, nextID: nextID) == .now }, next: kept.first { $0.id == nextID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            FeedBanner(online: online, error: error, readAt: readAt)
            glance
            pages
            calendar
            someday
        }
        .padding(.horizontal, 16)
        .animation(Motion.snap, value: route.section)
        .plannerSheets(actions: actions, yaad: yaad)
        .task(id: Reload(month: month, change: live?.yaad ?? 0)) { await load() }
        .onChange(of: route.day) { _, day in
            if let day { month = MonthPaging.first(of: day) }
        }
    }

    private var glance: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let glance = Self.nowNext(actions.shown(todayPlans), now: context.date)
            Button { choose(Self.picking(day: .now, from: route)) } label: {
                VStack(alignment: .leading, spacing: 12) {
                    glanceRow("Now", plan: glance.current, detail: glance.current.map { PlanTime.status($0, now: context.date, state: .now) }, empty: "Nothing on now")
                    glanceRow("Next", plan: glance.next, detail: glance.next.map { PlanTime.status($0, now: context.date, state: .next) }, empty: "Nothing else today")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .opacity(online ? 1 : 0.6)
            .accessibilityHint("Opens today")
        }
    }

    private func glanceRow(_ label: String, plan: Plan?, detail: String?, empty: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.inkFaint).frame(width: 36, alignment: .leading)
            if let plan, let detail {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title).font(.subheadline.weight(.medium)).foregroundStyle(.ink).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.inkMuted).lineLimit(1)
                }
            } else {
                Text(empty).font(.subheadline).foregroundStyle(.inkMuted)
            }
        }
    }

    private var pages: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(PlannerSection.allCases, id: \.self) { section in
                row(section.rawValue, symbol: section.symbol, current: route.section == section) { choose(Self.picking(section, from: route)) }
            }
        }
    }

    private var calendar: some View {
        MiniCalendar(month: $month, marked: MiniCalendar.marks(actions.shown(monthPlans), days: PlannerLayout.monthGrid(month)), selected: Self.selectedDay(route), pick: { day in
            choose(Self.picking(day: day, from: route))
        }, today: {
            month = MonthPaging.first(of: .now)
            choose(PlannerRoute())
        })
        .padding(.horizontal, 8)
        .opacity(online ? 1 : 0.6)
    }

    private var someday: some View {
        Button { actions.sheet = .someday } label: {
            rowLabel("Someday", symbol: PlannerMode.somedaySymbol, detail: somedayCount.map(String.init), current: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Someday\(somedayCount.map { ", \($0)" } ?? "")")
    }

    private func row(_ title: String, symbol: String, current: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, symbol: symbol, detail: nil, current: current) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(current ? .isSelected : [])
    }

    /// A drawer row: a symbol, a title and a trailing value; the page shown is set apart by sage and weight, not a fill.
    private func rowLabel(_ title: String, symbol: String, detail: String?, current: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(current ? Color.sageDeep : .inkMuted).frame(width: 24)
            Text(title).font(.body.weight(current ? .semibold : .regular)).foregroundStyle(.ink).lineLimit(1)
            Spacer()
            if let detail { Text(detail).font(.subheadline.monospacedDigit()).foregroundStyle(.inkMuted).contentTransition(.numericText()) }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .animation(Motion.snap, value: current)
    }

    private struct Reload: Hashable {
        let month: Date
        let change: Int
    }

    private func load() async {
        let today = Calendar.current.startOfDay(for: .now)
        let days = PlannerLayout.monthGrid(month)
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today), let first = days.first, let last = days.last, let end = Calendar.current.date(byAdding: .day, value: 1, to: last) else { return }
        do {
            async let todays = yaad.plans(from: today, to: tomorrow)
            async let monthly = yaad.plans(from: first, to: end)
            async let count = SomedayCount.of(yaad)
            let (t, m, c) = try await (todays, monthly, count)
            actions.settle(t + m)
            todayPlans = t
            monthPlans = m
            somedayCount = c
            error = nil
            readAt = .now
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
