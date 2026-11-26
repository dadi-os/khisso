import Foundation

/// How Chats lists its conversations, as thaali's sidebar does: under the day of their last message,
/// each row dotted by what its agent is doing.
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

    /// How the drawer narrows the chat list: by unread replies or by what the agent is doing.
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case unread = "Unread"
        case working = "Working"
        case waiting = "Waiting"
        case idle = "Idle"

        var id: String { rawValue }

        /// Whether the filter keeps `thread`, whose agent is in `state`.
        func keeps(_ thread: ThreadSummary, state: AgentState) -> Bool {
            switch self {
            case .all: true
            case .unread: thread.unread > 0
            case .working: state == .working
            case .waiting: state == .waiting
            case .idle: state == .idle
            }
        }

        /// How many of `threads` the filter keeps, whatever the search says.
        func count(in threads: [ThreadSummary], state: (String) -> AgentState) -> Int {
            threads.filter { keeps($0, state: state($0.agentId)) }.count
        }
    }

    /// A row's one line, as thaali's list says it: the ask while the agent works, what it waits on while it waits, who
    /// stopped it, else its last message.
    static func line(_ thread: ThreadSummary, running: AgentRecord.Running, now: Date = .now) -> String {
        if running.working {
            guard let ask = running.job?.opened.content else { return "working" }
            return Agent.preview(ask)
        }
        if running.mark(at: now) == .stopped, let stopped = running.job?.stopped {
            return "Stopped \(AgentTime.relative(stopped.at, now: now))"
        }
        return ActivityLabel.text(running, counts: nil) ?? ((thread.fromUser ? "You: " : "") + Agent.preview(thread.lastMessage))
    }

    /// A conversation's last activity for the right edge of its row: the time today, "Yesterday", else the day.
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let label = dayLabel(date, now: now, calendar: calendar)
        guard label == "Today" else {
            return label
        }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone))
    }
}
