import Foundation

/// Labelled, human phrases for durations and moments, so no value in the Planner is shown bare. The same words
/// as thaali's `planner/phrases.ts`.
enum Phrase {
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 86_400

    /// A length of time in words: "25 min", "1 h 30 min", "3 h", "2 days"; under a minute is "under a minute".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((abs(seconds) / minute).rounded())
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        if minutes < 24 * 60 {
            let (hours, rest) = (minutes / 60, minutes % 60)
            return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
        }
        let days = Int((abs(seconds) / day).rounded())
        return days == 1 ? "1 day" : "\(days) days"
    }

    /// A length for "in" and "ago" phrases: exact minutes below three hours, whole hours from there ("8 h", not
    /// "8 h 7 min"), then days.
    static func coarse(_ seconds: TimeInterval) -> String {
        let minutes = Int((abs(seconds) / minute).rounded())
        return minutes >= 180 && minutes < 24 * 60 ? "\(Int((Double(minutes) / 60).rounded())) h" : duration(seconds)
    }

    /// "in 25 min", "in 2 days", or "now" when under a minute away.
    static func inPhrase(_ seconds: TimeInterval) -> String {
        abs(seconds) < minute ? "now" : "in \(coarse(seconds))"
    }

    /// "25 min ago", "3 days ago", or "just now" when under a minute ago.
    static func agoPhrase(_ seconds: TimeInterval) -> String {
        abs(seconds) < minute ? "just now" : "\(coarse(seconds)) ago"
    }

    /// A clock time such as "11:59 PM", in the calendar's zone.
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone))
    }

    /// A day named relative to `now`: "today", "tomorrow", "yesterday", a weekday within the week, else "Nov 28".
    static func dayWord(_ at: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: at)).day ?? 0
        let locale = calendar.locale ?? .current
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case 2..<7: return at.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated))
        default: return at.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day())
        }
    }

    /// A moment as day and clock: "today 3:30 PM", "Fri 11:59 PM".
    static func moment(_ at: Date, now: Date, calendar: Calendar = .current) -> String {
        "\(dayWord(at, now: now, calendar: calendar)) \(clock(at, calendar: calendar))"
    }

    /// "Last confirmed 3 days ago"; nil when the task never was.
    static func confirmed(_ at: Date?, now: Date) -> String? {
        at.map { "Last confirmed \(agoPhrase(now.timeIntervalSince($0)))" }
    }
}
