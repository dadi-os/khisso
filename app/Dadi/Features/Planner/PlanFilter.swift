import Foundation

/// What one Week day header says about all-day and multi-day plans.
struct AllDayMark: Equatable {
    /// Their titles, for the accessibility label and the long-press.
    let titles: [String]
    /// A mark runs on from the day before.
    let fromPrev: Bool
    /// A mark runs into the next day.
    let toNext: Bool
}

/// The one place that says which of the plans Yaad returns a view draws, as thaali's `planner/plans.ts`: the grid
/// and the widget draw timed plans with an end, the all-day band and the Week marks draw all-day and multi-day
/// plans, Month draws everything.
enum PlanFilter {
    /// A plan's start and end; an all-day plan covers its first day through its last.
    static func span(_ plan: Plan, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let end = plan.endAt ?? plan.startAt
        guard plan.allDay else { return (plan.startAt, end) }
        let lastDay = calendar.startOfDay(for: end)
        return (calendar.startOfDay(for: plan.startAt), calendar.date(byAdding: .day, value: 1, to: lastDay)!.addingTimeInterval(-0.001))
    }

    /// True when any part of `plan` falls on `day`, so a multi-day plan shows on each of its days.
    static func overlaps(_ plan: Plan, day: Date, calendar: Calendar = .current) -> Bool {
        let (start, end) = span(plan, calendar: calendar)
        let from = calendar.startOfDay(for: day)
        let to = calendar.date(byAdding: .day, value: 1, to: from)!
        return start < to && end >= from
    }

    /// True when `plan` draws as a bar rather than on the time axis: all day, or running past midnight.
    static func runsAsBar(_ plan: Plan, calendar: Calendar = .current) -> Bool {
        guard !plan.allDay else { return true }
        guard let end = plan.endAt, let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: plan.startAt)) else { return false }
        return end > next
    }

    /// The plans the time grid draws: timed, with a start and an end (the grid clips one that runs past midnight).
    static func grid(_ plans: [Plan]) -> [Plan] {
        plans.filter { !$0.allDay && $0.endAt != nil }
    }

    /// The plans the all-day band draws: all-day plans and plans that run past a day.
    static func band(_ plans: [Plan], calendar: Calendar = .current) -> [Plan] {
        plans.filter { runsAsBar($0, calendar: calendar) }
    }

    /// The plans with a start and nothing to draw on an axis: no end, and not all day. They wait in Someday.
    static func loose(_ plans: [Plan]) -> [Plan] {
        plans.filter { $0.endAt == nil && !$0.allDay }.sorted { $0.startAt < $1.startAt }
    }

    /// Plans on `day`, earliest first.
    static func on(_ plans: [Plan], day: Date, calendar: Calendar = .current) -> [Plan] {
        plans.filter { overlaps($0, day: day, calendar: calendar) }.sorted { $0.startAt < $1.startAt }
    }

    /// One month tile's plans, all-day ones first: the first `limit` and how many more there are.
    static func monthTile(_ plans: [Plan], day: Date, limit: Int, calendar: Calendar = .current) -> (shown: [Plan], more: Int) {
        let own = on(plans, day: day, calendar: calendar).sorted { runsAsBar($0, calendar: calendar) && !runsAsBar($1, calendar: calendar) }
        return (Array(own.prefix(limit)), max(0, own.count - limit))
    }

    /// The first and last of `days` (indexes) a bar plan covers; nil when it touches none of them.
    static func barColumns(_ plan: Plan, in days: [Date], calendar: Calendar = .current) -> ClosedRange<Int>? {
        let columns = days.indices.filter { overlaps(plan, day: days[$0], calendar: calendar) }
        guard let first = columns.first, let last = columns.last else { return nil }
        return first...last
    }

    /// Bar plans touching `days`, stacked into lanes, earliest first: plans in one lane share no shown day.
    static func spanLanes(_ plans: [Plan], in days: [Date], calendar: Calendar = .current) -> [[(plan: Plan, columns: ClosedRange<Int>)]] {
        var lanes: [[(plan: Plan, columns: ClosedRange<Int>)]] = []
        for plan in band(plans, calendar: calendar).sorted(by: { $0.startAt < $1.startAt }) {
            guard let mine = barColumns(plan, in: days, calendar: calendar) else { continue }
            if let lane = lanes.firstIndex(where: { $0.allSatisfy { !$0.columns.overlaps(mine) } }) {
                lanes[lane].append((plan, mine))
            } else {
                lanes.append([(plan, mine)])
            }
        }
        return lanes
    }

    /// One entry per day of `days`: the bar plans touching it, or nil when none does. A multi-day plan marks every
    /// shown day it covers and joins neighbouring days, so the header draws one continuous hairline.
    static func allDayMarks(_ plans: [Plan], days: [Date], calendar: Calendar = .current) -> [AllDayMark?] {
        let bars = band(plans, calendar: calendar).compactMap { plan in barColumns(plan, in: days, calendar: calendar).map { (plan: plan, columns: $0) } }
        return days.indices.map { index in
            let here = bars.filter { $0.columns.contains(index) }
            guard !here.isEmpty else { return nil }
            return AllDayMark(titles: here.map(\.plan.title), fromPrev: here.contains { $0.columns.lowerBound < index }, toNext: here.contains { $0.columns.upperBound > index })
        }
    }

    /// Whether a bar plan continues before `day` and after it, so its bar draws open ended on those sides.
    static func barEdges(_ plan: Plan, day: Date, calendar: Calendar = .current) -> (before: Bool, after: Bool) {
        let (start, end) = span(plan, calendar: calendar)
        let from = calendar.startOfDay(for: day)
        let to = calendar.date(byAdding: .day, value: 1, to: from)!
        return (start < from, end >= to)
    }

    /// A multi-day plan's span in words ("Nov 21 – 22", "Nov 30 – Dec 2"); nil for a plan inside one day.
    static func spanRange(_ plan: Plan, calendar: Calendar = .current) -> String? {
        let (start, end) = span(plan, calendar: calendar)
        guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)), end >= next else { return nil }
        let month = Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated)
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        return "\(start.formatted(month)) \(calendar.component(.day, from: start)) – \(sameMonth ? "" : end.formatted(month) + " ")\(calendar.component(.day, from: end))"
    }

    /// True when `plan` is the one on at `now`.
    static func isCurrent(_ plan: Plan, now: Date) -> Bool {
        guard !plan.allDay, let end = plan.endAt else { return false }
        return plan.startAt <= now && now < end
    }
}

/// Calendar arithmetic the Planner's views share.
enum PlannerCalendar {
    /// Monday at local midnight of the week holding `date`.
    static func monday(of date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -((calendar.component(.weekday, from: start) + 5) % 7), to: start)!
    }
}

/// Who a plan or task's owner is for messaging.
enum PlanOwner {
    /// Owners that are a source, not an agent: nothing to message.
    static let sources: Set<String> = ["manual", "ingest"]

    /// The agent to message about something owned by `owner`: its id while that agent is running; nil for a
    /// source and for an agent that has retired.
    static func agent(_ owner: String, active: (String) -> Bool) -> String? {
        sources.contains(owner) || !active(owner) ? nil : owner
    }

    /// The agent id that keeps `owner`'s item, or nil when it is a source no agent keeps.
    static func keptBy(_ owner: String) -> String? {
        sources.contains(owner) ? nil : owner
    }
}

extension Plan {
    /// "Attended", "Didn't attend", or nil while Ankur has not said.
    var attendedLabel: String? {
        attended.map { $0 ? "Attended" : "Didn’t attend" }
    }
}
