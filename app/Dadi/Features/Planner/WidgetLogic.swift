import Foundation

/// One line of the Planner widget: a plan, or the free time between two plans.
enum WidgetRow: Equatable {
    case plan(Plan, current: Bool)
    case free(minutes: Int)
}

/// What the widget draws, and how many plans fall outside its window.
struct WidgetWindow: Equatable {
    var rows: [WidgetRow]
    var earlier: Int
    var later: Int
}

/// Which of today's plans fit the Planner widget, and the window it follows when they do not, as thaali's `widget.ts`.
enum WidgetLogic {
    static let planHeight: CGFloat = 56
    static let currentHeight: CGFloat = 64
    static let freeHeight: CGFloat = 28
    static let chipHeight: CGFloat = 24
    static let gap: CGFloat = 2
    /// The least gap between two plans the widget names as free time, in minutes.
    static let freeMinimum = 15

    /// Today's plans the widget shows: timed, with a start and an end, overlapping `day`, earliest first.
    static func tilePlans(_ plans: [Plan], on day: Date, calendar: Calendar = .current) -> [Plan] {
        let from = calendar.startOfDay(for: day)
        let to = calendar.date(byAdding: .day, value: 1, to: from)!
        return plans
            .filter { plan in
                guard !plan.allDay, let end = plan.endAt else { return false }
                return plan.startAt < to && end > from
            }
            .sorted { $0.startAt < $1.startAt }
    }

    /// The plans and the free stretches between those not declined, in time order.
    static func sequence(_ plans: [Plan], now: Date) -> [WidgetRow] {
        var entries: [(at: Date, row: WidgetRow)] = plans.map { ($0.startAt, .plan($0, current: PlanFilter.isCurrent($0, now: now))) }
        let kept = plans.filter { !$0.declined }
        if var reach = kept.first.map({ PlanFilter.span($0).end }) {
            for plan in kept.dropFirst() {
                let (start, end) = PlanFilter.span(plan)
                let minutes = Int((start.timeIntervalSince(reach) / 60).rounded())
                if minutes >= freeMinimum { entries.append((reach, .free(minutes: minutes))) }
                reach = max(reach, end)
            }
        }
        return entries.sorted { $0.at < $1.at }.map(\.row)
    }

    private static func height(_ row: WidgetRow) -> CGFloat {
        switch row {
        case .free: freeHeight
        case .plan(_, let current): current ? currentHeight : planHeight
        }
    }

    private static func stack(_ rows: ArraySlice<WidgetRow>) -> CGFloat {
        rows.reduce(0) { $0 + height($1) } + CGFloat(max(0, rows.count - 1)) * gap
    }

    private static func planCount(_ rows: ArraySlice<WidgetRow>) -> Int {
        rows.filter { if case .plan = $0 { true } else { false } }.count
    }

    private static func anchor(_ rows: [WidgetRow], now: Date) -> Int {
        if let current = rows.firstIndex(where: { if case .plan(_, true) = $0 { true } else { false } }) { return current }
        if let next = rows.firstIndex(where: { if case .plan(let plan, _) = $0 { PlanFilter.span(plan).end > now } else { false } }) { return next }
        return rows.count - 1
    }

    /// The rows of today that fit `capacity` points. When they all fit, every row. Otherwise a window that grows
    /// from the plan on now (or the next one, or the last once the day is over), taking the row after it, then the
    /// one before, alternately while they fit with their "earlier" and "later" chips; free time at an edge is dropped.
    static func window(_ plans: [Plan], now: Date, capacity: CGFloat) -> WidgetWindow {
        let rows = sequence(plans, now: now)
        if rows.isEmpty || stack(rows[...]) <= capacity { return WidgetWindow(rows: rows, earlier: 0, later: 0) }
        func fits(_ a: Int, _ b: Int) -> Bool {
            let chips = (planCount(rows[..<a]) > 0 ? 1 : 0) + (planCount(rows[(b + 1)...]) > 0 ? 1 : 0)
            return stack(rows[a...b]) + CGFloat(chips) * (chipHeight + gap) <= capacity
        }
        var a = anchor(rows, now: now)
        var b = a
        var forward = true
        var stuck = 0
        while stuck < 2 {
            let (na, nb) = forward ? (a, b + 1) : (a - 1, b)
            if na >= 0, nb < rows.count, fits(na, nb) {
                (a, b) = (na, nb)
                stuck = 0
            } else {
                stuck += 1
            }
            forward.toggle()
        }
        while a < b, case .free = rows[a] { a += 1 }
        while b > a, case .free = rows[b] { b -= 1 }
        return WidgetWindow(rows: Array(rows[a...b]), earlier: planCount(rows[..<a]), later: planCount(rows[(b + 1)...]))
    }
}

extension WidgetLogic {
    /// One line recapping a day that is over: "11 plans done · 11 attended · 0 of 8 tasks"; declined plans do not count.
    static func recap(_ plans: [Plan], tasks: (done: Int, total: Int)) -> String {
        let kept = plans.filter { !$0.declined }
        let attended = kept.filter { $0.attended == true }.count
        let list = ["\(kept.count) \(kept.count == 1 ? "plan" : "plans") done", attended == 0 ? nil : "\(attended) attended"].compactMap { $0 }
        return (list + ["\(tasks.done) of \(tasks.total) tasks"]).joined(separator: " · ")
    }

    /// True once every kept plan of the day has ended and there was at least one.
    static func dayOver(_ plans: [Plan], now: Date) -> Bool {
        let kept = plans.filter { !$0.declined }
        return !kept.isEmpty && kept.allSatisfy { ($0.endAt ?? $0.startAt) <= now }
    }
}
