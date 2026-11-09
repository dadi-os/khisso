import Foundation

/// A clock change inside one calendar day: the wall-clock hour a fall-back
/// repeats or a spring-forward skips, and the zone names either side of it.
struct ClockChange: Equatable {
    enum Kind: Equatable {
        case repeated
        case skipped
    }

    let kind: Kind
    /// The wall-clock hour (0-23) that happens twice or not at all.
    let hour: Int
    /// The zone's short name before the change and after it.
    let before: String
    let after: String

    /// The change inside `day`, or nil on a 24-hour day.
    static func on(_ day: Date, calendar: Calendar = .current) -> ClockChange? {
        let zone = calendar.timeZone
        let start = calendar.startOfDay(for: day)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start),
              let change = zone.nextDaylightSavingTimeTransition(after: start), change < next else { return nil }
        let justBefore = change.addingTimeInterval(-1)
        let falling = zone.secondsFromGMT(for: change) < zone.secondsFromGMT(for: justBefore)
        let landed = calendar.component(.hour, from: change)
        return ClockChange(
            kind: falling ? .repeated : .skipped,
            hour: falling ? landed : landed - 1,
            before: zone.abbreviation(for: justBefore) ?? zone.identifier,
            after: zone.abbreviation(for: change) ?? zone.identifier
        )
    }

    /// What the band on the axis says.
    var caption: String {
        switch kind {
        case .repeated: "\(Self.hourName(hour)) happens twice: \(before), then \(after)"
        case .skipped: "\(Self.hourName(hour)) is skipped: \(before) becomes \(after)"
        }
    }

    /// "EST", or "EDT → EST" when the zone changes between `first` and `last`.
    static func zoneName(from first: Date, to last: Date, calendar: Calendar = .current) -> String {
        let zone = calendar.timeZone
        let a = zone.abbreviation(for: first) ?? zone.identifier
        let b = zone.abbreviation(for: last) ?? zone.identifier
        return a == b ? a : "\(a) \u{2192} \(b)"
    }

    private static func hourName(_ hour: Int) -> String {
        "\(hour % 12 == 0 ? 12 : hour % 12) \(hour < 12 ? "AM" : "PM")"
    }
}
