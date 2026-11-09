import Foundation

/// How Chats lists its conversations, as thaali's sidebar does: under the day of their last message,
/// each row dotted while a lane of its agent runs.
enum ChatGroups {
    /// The conversations of one day, under that day's heading.
    struct Day: Identifiable, Equatable {
        let label: String
        let threads: [ThreadSummary]
        var id: String { label }
    }

    /// The heading of the day `date` falls on: "Today", "Yesterday", else the day itself ("Mon, Oct 26").
    static func dayLabel(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        return date.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).month(.abbreviated).day())
    }

    /// `threads` whose agent name holds `query`, grouped under the day of their last message, keeping
    /// their order (newest first) with one group per day.
    static func days(_ threads: [ThreadSummary], matching query: String, now: Date = .now, calendar: Calendar = .current) -> [Day] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        var days: [Day] = []
        for thread in threads where needle.isEmpty || thread.agentName.lowercased().contains(needle) {
            let label = dayLabel(thread.lastAt, now: now, calendar: calendar)
            if let index = days.firstIndex(where: { $0.label == label }) {
                days[index] = Day(label: label, threads: days[index].threads + [thread])
            } else {
                days.append(Day(label: label, threads: [thread]))
            }
        }
        return days
    }

    /// True while an agent lane runs, work or process: the row opens with a pulsing dot.
    static func isWorking(_ lanes: Set<Lane>) -> Bool {
        lanes.contains(.work) || lanes.contains(.process)
    }

    /// A conversation's last activity for the right edge of its row: the time today, "Yesterday", else the day.
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let label = dayLabel(date, now: now, calendar: calendar)
        return label == "Today" ? date.formatted(date: .omitted, time: .shortened) : label
    }
}
