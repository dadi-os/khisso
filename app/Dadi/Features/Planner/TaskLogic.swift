import Foundation

/// A day's checklist in its three groups.
struct TaskGroups: Equatable {
    /// Not done and closed before the day, or flagged past due: shown on top until done.
    var pastDue: [PlanTask] = []
    /// Not done and open on the day, soonest close first.
    var open: [PlanTask] = []
    /// Done, struck through and folded.
    var done: [PlanTask] = []
}

/// The open-task count a week day header carries.
struct DayBadge: Equatable {
    /// Tasks not done whose window holds the day (past due ones too, on today).
    var open: Int
    /// Some counted task closes that day or is past due: drawn in clay.
    var urgent: Bool
    /// Tasks exist for the day and every one is done.
    var allDone: Bool
}

/// The count a month tile carries: tasks closing that day.
struct MonthBadge: Equatable {
    var closing: Int
    var pastDue: Bool
    var allDone: Bool
}

/// What the checklist decides without drawing, matching thaali's `planner/tasks.ts`.
enum TaskLogic {
    /// The local date of `day` as YYYY-MM-DD, the form Yaad's task requests and `opensOn` use.
    static func key(_ day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    /// The local day a task closes; nil when it is open-ended.
    static func closeDay(_ task: PlanTask, calendar: Calendar = .current) -> Date? {
        task.closesAt.map { calendar.startOfDay(for: $0) }
    }

    /// Earliest close first, open-ended last, then by title.
    static func byClose(_ a: PlanTask, _ b: PlanTask) -> Bool {
        if a.closesAt != b.closesAt {
            guard let x = a.closesAt else { return false }
            guard let y = b.closesAt else { return true }
            return x < y
        }
        return a.title.localizedCompare(b.title) == .orderedAscending
    }

    /// `tasks` as `day` groups them. A task with no window belongs to Someday and is left out; one that
    /// opens after `day` is not on the list yet.
    static func groups(_ tasks: [PlanTask], on day: Date, calendar: Calendar = .current) -> TaskGroups {
        let dayKey = key(day, calendar: calendar)
        let start = calendar.startOfDay(for: day)
        var groups = TaskGroups()
        for task in tasks {
            let closes = closeDay(task, calendar: calendar)
            if closes == nil { continue }
            if task.done {
                groups.done.append(task)
            } else if task.pastDue || closes.map({ $0 < start }) == true {
                groups.pastDue.append(task)
            } else if task.opensOn.map({ $0 <= dayKey }) ?? true {
                groups.open.append(task)
            }
        }
        groups.pastDue.sort(by: byClose)
        groups.open.sort(by: byClose)
        groups.done.sort(by: byClose)
        return groups
    }

    /// How many of a day's tasks are ticked, out of every task the list shows.
    static func progress(_ groups: TaskGroups) -> (done: Int, total: Int) {
        (groups.done.count, groups.pastDue.count + groups.open.count + groups.done.count)
    }

    /// True for a task with no close: it is Someday wherever tasks are counted or listed, whether or not it has an opening.
    static func isSomeday(_ task: PlanTask) -> Bool {
        task.closesAt == nil
    }

    /// The Someday tasks among `tasks`, not done, each once, by title: the one place that says which tasks are Someday.
    static func someday(_ tasks: [PlanTask]) -> [PlanTask] {
        var seen = Set<String>()
        return tasks.filter { isSomeday($0) && !$0.done && seen.insert($0.id).inserted }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    /// The week badge for `day` from that day's task list.
    static func dayBadge(_ tasks: [PlanTask], on day: Date, now: Date, calendar: Calendar = .current) -> DayBadge {
        let dayKey = key(day, calendar: calendar)
        let start = calendar.startOfDay(for: day)
        let today = calendar.isDate(day, inSameDayAs: now)
        let counted = tasks.filter { task in
            if task.done { return false }
            guard let closes = closeDay(task, calendar: calendar) else { return false }
            let inWindow = (task.opensOn.map { $0 <= dayKey } ?? true) && (closes >= start)
            return inWindow || (today && task.pastDue)
        }
        let urgent = counted.contains { task in
            task.pastDue || task.closesAt.map { calendar.isDate($0, inSameDayAs: day) } == true
        }
        return DayBadge(open: counted.count, urgent: urgent, allDone: counted.isEmpty && tasks.contains { $0.done && !isSomeday($0) })
    }

    /// The month badge for `day` from that day's task list: tasks closing that day.
    static func monthBadge(_ tasks: [PlanTask], on day: Date, calendar: Calendar = .current) -> MonthBadge {
        let closing = tasks.filter { $0.closesAt.map { calendar.isDate($0, inSameDayAs: day) } == true }
        return MonthBadge(closing: closing.count, pastDue: closing.contains { !$0.done && $0.pastDue }, allDone: !closing.isEmpty && closing.allSatisfy(\.done))
    }

    /// The title with case, digits and punctuation removed, the key repeated items share.
    static func titleKey(_ title: String) -> String {
        let letters = title.lowercased().map { $0.isLetter || $0.isWhitespace ? $0 : " " }
        return String(letters).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// `items` grouped by near-identical title, so forty repeats read as one row; groups sort by label, and a
    /// group's label is its first title without a trailing number ("Gym training split").
    static func groupByTitle<T: Titled>(_ items: [T]) -> [TitleGroup<T>] {
        var order: [String] = []
        var grouped: [String: [T]] = [:]
        for item in items {
            let key = titleKey(item.title).isEmpty ? item.title : titleKey(item.title)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(item)
        }
        return order
            .map { key in
                let group = grouped[key]!
                let label = group.count > 1 ? trimmedNumber(group[0].title) : group[0].title
                return TitleGroup(id: key, label: label, items: group)
            }
            .sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
    }

    private static func trimmedNumber(_ title: String) -> String {
        let trimmed = title.replacingOccurrences(of: #"[\s#:–-]*\d+\s*$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    /// "checked 3d ago" for a Someday task last verified a day or more ago; nil otherwise.
    static func checkedAgo(_ task: PlanTask, now: Date) -> String? {
        guard let at = task.verifiedAt, now.timeIntervalSince(at) >= 86_400 else { return nil }
        return "checked \(Int(now.timeIntervalSince(at) / 86_400))d ago"
    }

    /// The course a task row names after its status, or nil when the title already says it: a title that starts
    /// with the hub's course code ("IBIO 150 — …" under "IBIO 150 class") or contains the hub's whole title.
    static func courseLabel(_ task: PlanTask) -> String? {
        guard let hub = task.hub?.title.trimmingCharacters(in: .whitespaces) else { return nil }
        let code = hub.replacingOccurrences(of: #"\s+(class|course|lecture|lab|section)$"#, with: "", options: [.regularExpression, .caseInsensitive])
        let title = task.title.lowercased()
        if title.contains(hub.lowercased()) || title.hasPrefix(code.lowercased()) { return nil }
        return hub
    }

    /// The one meta line under a task's title: its status with the course when the title does not name it
    /// ("Past due by 12 days · IBIO 150").
    static func meta(_ task: PlanTask, now: Date, calendar: Calendar = .current) -> String? {
        let status = PlanTime.taskStatus(task, now: now, calendar: calendar)
        if status.tone == .none { return courseLabel(task) }
        return [status.label, courseLabel(task)].compactMap { $0 }.joined(separator: " · ")
    }

    /// True when a task not done has passed its close or closes within six hours: its meta line is tinted late.
    static func isUrgent(_ task: PlanTask, now: Date) -> Bool {
        guard !task.done, let close = task.closesAt else { return false }
        return close.timeIntervalSince(now) < 6 * 3600 || task.pastDue
    }
}

/// Something with a title the Someday sheet can group.
protocol Titled {
    var title: String { get }
}

extension Plan: Titled {}
extension PlanTask: Titled {}

/// Items whose titles match once case, digits and punctuation are ignored: "Weigh-in 3" and "weigh in 12".
struct TitleGroup<T>: Identifiable {
    let id: String
    let label: String
    let items: [T]
}
