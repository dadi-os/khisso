import SwiftUI

/// The ways to look at the Planner's timeline, chosen from the page's name bubble or its drawer.
enum PlannerMode: String, CaseIterable, Hashable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    /// The symbol of the Someday button.
    static let somedaySymbol = "tray"

    var symbol: String {
        switch self {
        case .day: "clock"
        case .week: "calendar.day.timeline.left"
        case .month: "calendar"
        }
    }
}

/// What the Planner page shows: its plans or its tasks, one at a time; the side drawer switches between them.
enum PlannerSection: String, CaseIterable, Hashable {
    case timeline = "Timeline"
    case checklist = "Checklist"

    var symbol: String {
        switch self {
        case .timeline: "calendar"
        case .checklist: "checklist"
        }
    }
}

/// Where the Planner is: the section, the timeline's view, and the day Day was opened on from Week or Month. The one
/// state the drawer, the name bubble, Week and Month and a re-tap of the Planner tab all change.
struct PlannerRoute: Equatable {
    var section = PlannerSection.timeline
    var mode = PlannerMode.day
    /// The day Day shows when it was opened from another view; nil for today.
    var day: Date?

    /// Shows the timeline in `mode`, on today.
    mutating func show(_ mode: PlannerMode) {
        section = .timeline
        self.mode = mode
        day = nil
    }

    /// Shows the Checklist.
    mutating func showChecklist() {
        section = .checklist
    }

    /// Shows `day` in the Day view.
    mutating func open(day: Date, calendar: Calendar = .current) {
        section = .timeline
        mode = .day
        self.day = calendar.startOfDay(for: day)
    }

    /// True when the Planner is on its root: Day on today.
    func isRoot(calendar: Calendar = .current, now: Date = .now) -> Bool {
        section == .timeline && mode == .day && (day.map { calendar.isDate($0, inSameDayAs: now) } ?? true)
    }

    /// A tap on the already selected Planner tab: anywhere but the root it returns to Timeline, Day, today and answers
    /// false; at the root it changes nothing and answers true, so the page scrolls to now.
    mutating func reselect(calendar: Calendar = .current, now: Date = .now) -> Bool {
        if isRoot(calendar: calendar, now: now) { return true }
        show(.day)
        return false
    }
}

/// The Planner: its plans (Day, Week, Month) or its tasks (the Checklist), one at a time. Plans and tasks are
/// read-only here: Ankur ticks a task, says whether he attended a plan, and messages the agent that keeps either. A
/// task swipes right to tick and left to message its agent; a plan or task taps open its sheet and a plan long-presses
/// for a menu.
struct PlannerPage: View {
    let yaad: YaadClient
    @Binding var route: PlannerRoute
    /// Bumped to scroll the Day view to now.
    let scrollNow: Int
    /// False while dadi is out of reach: every view shows the last answer.
    let online: Bool

    @State private var actions: PlannerActions

    /// - Parameters:
    ///   - message: opens the thread of the agent with this id, with the text ready in its composer when given.
    ///   - reachable: whether an agent can still be messaged.
    ///   - nameOf: an agent's name for display.
    init(yaad: YaadClient, route: Binding<PlannerRoute>, scrollNow: Int, online: Bool, message: @escaping (String, String?) -> Void, reachable: @escaping (String) -> Bool, nameOf: @escaping (String) -> String) {
        self.yaad = yaad
        _route = route
        self.scrollNow = scrollNow
        self.online = online
        _actions = State(initialValue: PlannerActions(yaad: yaad, message: message, reachable: reachable, nameOf: nameOf))
    }

    var body: some View {
        Group {
            switch route.section {
            case .checklist:
                ChecklistView(yaad: yaad, actions: actions, online: online)
                    .transition(.opacity)
            case .timeline:
                switch route.mode {
                case .day:
                    DayView(yaad: yaad, actions: actions, online: online, day: route.day ?? .now, scrollNow: scrollNow)
                        .id(route.day)
                        .transition(.opacity)
                case .week:
                    WeekView(yaad: yaad, actions: actions, online: online, openDay: show(_:))
                        .transition(.opacity)
                case .month:
                    MonthView(yaad: yaad, actions: actions, online: online, openDay: show(_:))
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            MarkBanner(actions: actions)
                .animation(Motion.settle, value: actions.ticker.undo)
                .animation(Motion.settle, value: actions.ticker.failure)
                .animation(Motion.settle, value: actions.attendedFailure)
        }
        .plannerSheets(actions: actions, yaad: yaad)
        .onAppear {
            actions.openDay = { day in
                actions.sheet = nil
                show(day)
            }
        }
        .sensoryFeedback(.selection, trigger: route)
        .navigationTitle("Planner")
    }

    /// Shows `day` in the Day view.
    private func show(_ day: Date) {
        withAnimation(Motion.settle) { route.open(day: day) }
    }
}
