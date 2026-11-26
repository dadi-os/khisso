import Foundation

/// A routine's or reminder's schedule in the words the sheet uses.
enum RoutineFormat {
    private static let order: [Weekday] = [.mon, .tue, .wed, .thu, .fri, .sat, .sun]

    /// A routine's days in words: "Every day", "Weekdays", "Weekends", or the named days in week order.
    static func days(_ days: [Weekday]?) -> String {
        guard let days, !days.isEmpty, days.count != order.count else { return "Every day" }
        let kept = order.filter(days.contains)
        if kept == [.mon, .tue, .wed, .thu, .fri] { return "Weekdays" }
        if kept == [.sat, .sun] { return "Weekends" }
        return kept.map { $0.rawValue.capitalized }.joined(separator: ", ")
    }

    /// A routine's `HH:MM` (the box's local time) with its AM or PM mark: "07:30" reads "7:30 AM". Nil when
    /// the time is not `HH:MM`.
    static func time(_ at: String) -> String? {
        let parts = at.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return "\(parts[0] % 12 == 0 ? 12 : parts[0] % 12):\(String(format: "%02d", parts[1])) \(parts[0] < 12 ? "AM" : "PM")"
    }

    /// The routine's cadence: "Weekdays at 7:30 AM".
    static func cadence(_ routine: Routine) -> String {
        "\(days(routine.days)) at \(time(routine.at) ?? routine.at)"
    }

    /// A routine's next run in the fewest words: the weekday and clock within a week ("Mon 9:00 AM"), else the date as well.
    static func nextWords(_ date: Date, now: Date) -> String {
        date.timeIntervalSince(now) / 86_400 < 6
            ? "\(date.formatted(.dateTime.weekday(.abbreviated))) \(AgentTime.clock(date))"
            : AgentTime.clockWithDay(date, now: .distantPast)
    }

    /// When it runs next and when it last did: "Next Mon 9:00 AM · last ran 2 h ago", or "never ran".
    static func runs(_ routine: Routine, now: Date) -> String {
        "Next \(nextWords(routine.nextRunAt, now: now)) · \(routine.lastRunAt.map { "last ran \(AgentTime.relative($0, now: now))" } ?? "never ran")"
    }

    /// A reminder's time: "Tue, Nov 17, 4:00 PM".
    static func reminderWhen(_ reminder: Reminder) -> String {
        AgentTime.clockWithDay(reminder.runAt, now: .distantPast)
    }

    /// The routines Ankur can still act on: an ended one has nothing to cancel.
    static func active(_ routines: [Routine]) -> [Routine] {
        routines.filter(\.active)
    }
}
