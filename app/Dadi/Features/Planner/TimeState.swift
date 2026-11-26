import Foundation

/// Where a plan stands against the clock.
enum TimeState: Equatable {
    case past, now, next, later
}

/// What a task's status says about it.
struct TaskStatus: Equatable {
    enum Tone: Equatable {
        case done, late, soon, open, none
    }

    let label: String
    let tone: Tone
}

/// The one set of functions that say where a plan or task stands in time. Day, Week, the widget and every
/// sheet read them, as thaali reads `planner/timeState.ts`.
enum PlanTime {
    /// A plan's start and end; a plan with no end is a moment at its start.
    private static func bounds(_ plan: Plan) -> (start: Date, end: Date) {
        (plan.startAt, plan.endAt ?? plan.startAt)
    }

    /// The id of the plan that is "next": the earliest timed plan with an end, not declined, that starts later
    /// today. nil when none does.
    static func nextPlanID(_ plans: [Plan], now: Date, calendar: Calendar = .current) -> String? {
        plans
            .filter { !$0.allDay && $0.endAt != nil && !$0.declined && $0.startAt > now && calendar.isDate($0.startAt, inSameDayAs: now) }
            .min { $0.startAt < $1.startAt }?.id
    }

    /// Where `plan` stands: now while it is on, past once it has ended, next when it is `nextID`, otherwise
    /// later. A declined plan is never now or next.
    static func state(_ plan: Plan, now: Date, nextID: String?) -> TimeState {
        let (start, end) = bounds(plan)
        if end <= now && (plan.endAt != nil || start <= now) { return .past }
        if start <= now && now < end { return plan.declined ? .later : .now }
        return plan.id == nextID && !plan.declined ? .next : .later
    }

    /// The status a plan states about itself: "Now · 12 min left", "Starts in 25 min", "Starts tomorrow 9:00 AM",
    /// "Ended 2 h ago", "Ended yesterday", "All day".
    static func status(_ plan: Plan, now: Date, state: TimeState, calendar: Calendar = .current) -> String {
        let (start, end) = bounds(plan)
        if plan.allDay { return "All day" }
        switch state {
        case .now:
            return "Now · \(Phrase.duration(end.timeIntervalSince(now))) left"
        case .past:
            guard plan.endAt != nil else { return "Started \(Phrase.agoPhrase(now.timeIntervalSince(start)))" }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: end), to: calendar.startOfDay(for: now)).day ?? 0
            return days >= 1 ? "Ended \(Phrase.dayWord(end, now: now, calendar: calendar))" : "Ended \(Phrase.agoPhrase(now.timeIntervalSince(end)))"
        case .next, .later:
            return calendar.isDate(start, inSameDayAs: now)
                ? "Starts \(Phrase.inPhrase(start.timeIntervalSince(now)))"
                : "Starts \(Phrase.moment(start, now: now, calendar: calendar))"
        }
    }

    /// The status with what Ankur said after it ended: "Ended 8 h ago · Attended".
    static func situation(_ plan: Plan, now: Date, state: TimeState, calendar: Calendar = .current) -> String {
        [status(plan, now: now, state: state, calendar: calendar), state == .past ? plan.attendedLabel : nil].compactMap { $0 }.joined(separator: " · ")
    }

    /// The free seconds between consecutive timed plans that are at least `minimum` seconds long, in total;
    /// declined plans do not occupy time.
    static func freeBetween(_ plans: [Plan], minimum: TimeInterval) -> TimeInterval {
        let kept = plans.filter { !$0.allDay && $0.endAt != nil && !$0.declined }.sorted { $0.startAt < $1.startAt }
        guard var reach = kept.first?.endAt else { return 0 }
        var free: TimeInterval = 0
        for plan in kept.dropFirst() {
            let gap = plan.startAt.timeIntervalSince(reach)
            if gap >= minimum { free += gap }
            reach = max(reach, plan.endAt!)
        }
        return free
    }

    /// One true line about a day: its plans, the free time between them and the tasks left (with how many are
    /// past due). Parts that are zero are left out.
    static func daySummary(_ plans: [Plan], tasks: (open: Int, pastDue: Int)?) -> String {
        let counted = plans.filter { !$0.declined }
        var parts: [String] = []
        if !counted.isEmpty { parts.append("\(counted.count) \(counted.count == 1 ? "plan" : "plans")") }
        let free = freeBetween(plans, minimum: 30 * 60)
        if free > 0 { parts.append("\(Phrase.duration(free)) free between plans") }
        if let tasks, tasks.open + tasks.pastDue > 0 {
            let left = tasks.open + tasks.pastDue
            parts.append("\(left) \(left == 1 ? "task" : "tasks") to do\(tasks.pastDue > 0 ? ", \(tasks.pastDue) past due" : "")")
        }
        return parts.isEmpty ? "Nothing planned" : parts.joined(separator: " · ")
    }

    /// A task's situation in words: "Done", "Past due by 5 days", "Closes today 11:59 PM · in 17 min",
    /// "Closes Fri 11:59 PM · in 2 days", "No close date".
    static func taskStatus(_ task: PlanTask, now: Date, calendar: Calendar = .current) -> TaskStatus {
        if task.done { return TaskStatus(label: "Done", tone: .done) }
        guard let close = task.closesAt else { return TaskStatus(label: "No close date", tone: .none) }
        let left = close.timeIntervalSince(now)
        if left <= 0 { return TaskStatus(label: "Past due by \(Phrase.coarse(left))", tone: .late) }
        return TaskStatus(label: "Closes \(Phrase.moment(close, now: now, calendar: calendar)) · \(Phrase.inPhrase(left))", tone: left < 6 * 3600 ? .soon : .open)
    }

    /// One true line about a week or a month: its plans and the busiest day with that day's count.
    static func periodSummary(_ plans: [Plan], days: [Date], noun: String, calendar: Calendar = .current) -> String {
        let counted = plans.filter { !$0.declined && !$0.allDay }
        guard !counted.isEmpty, !days.isEmpty else { return "Nothing planned this \(noun)" }
        let perDay = days.map { day in (day: day, n: counted.filter { calendar.isDate($0.startAt, inSameDayAs: day) }.count) }
        let busiest = perDay.reduce(perDay[0]) { $1.n > $0.n ? $1 : $0 }
        let locale = calendar.locale ?? .current
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let name = noun == "month" ? busiest.day.formatted(style.weekday(.wide).month(.abbreviated).day()) : busiest.day.formatted(style.weekday(.wide))
        return "\(counted.count) \(counted.count == 1 ? "plan" : "plans") this \(noun) · busiest \(name) with \(busiest.n)"
    }
}
