import Foundation

/// The planner's pure logic, matching thaali's `planner/layout.ts`: a day's
/// timed plans as segments on a minute axis with side-by-side lanes for
/// overlaps, the open time between them, and what is now and next.
enum PlannerLayout {
    /// The least free time the grid names, in minutes.
    static let labeledGapMinimum = 30
    /// The least minutes a block is drawn for (28 pt at the Day grid's 56 pt an hour), so a short plan stays tappable.
    static let minimumSpan = 30
    /// Hours the axis shows on a day with no blocks.
    static let emptyHours = 7..<22

    /// One block's part of one day, in wall-clock minutes after local midnight (7:30 AM is 450 on a
    /// 23-, 24- or 25-hour day alike), with its lane.
    struct Segment: Hashable, Identifiable {
        let block: Plan
        let startMin: Int
        let endMin: Int
        /// Lane among the blocks it overlaps, and how many lanes that group has.
        var lane = 0
        var lanes = 1
        /// The least minutes the block is drawn for.
        var minimum = PlannerLayout.minimumSpan

        var id: String { block.id }

        /// Where the block's box ends on the axis: its own end, or its start plus `minimumSpan`.
        var drawnEndMin: Int { max(endMin, startMin + minimum) }
    }

    /// Open time between two blocks, in minutes after local midnight.
    struct Gap: Hashable {
        let startMin: Int
        let endMin: Int
    }

    /// `day`'s part of every timed plan that touches it, earliest first,
    /// with overlapping plans in side-by-side lanes. The planner view only
    /// holds plans with a start and an end.
    static func segments(_ blocks: [Plan], on day: Date, minimum: Int = minimumSpan, calendar: Calendar = .current) -> [Segment] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        func minutes(_ date: Date) -> Int {
            if date <= dayStart { return 0 }
            if date >= dayEnd { return 1440 }
            let clock = calendar.dateComponents([.hour, .minute], from: date)
            return (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
        }
        var segments = blocks
            .compactMap { block -> Segment? in
                guard !block.allDay, let end = block.endAt, block.startAt < dayEnd, end > dayStart else { return nil }
                let start = block.startAt
                return Segment(block: block, startMin: max(0, minutes(start)), endMin: min(1440, minutes(end)), minimum: minimum)
            }
            .sorted { ($0.startMin, $0.endMin) < ($1.startMin, $1.endMin) }

        var group: [Int] = []
        var laneEnds: [Int] = []
        var groupEnd = 0
        func close() {
            for index in group { segments[index].lanes = laneEnds.count }
            group = []
            laneEnds = []
        }
        for index in segments.indices {
            let segment = segments[index]
            if !group.isEmpty && segment.startMin >= groupEnd { close() }
            let lane = laneEnds.firstIndex { $0 <= segment.startMin } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(segment.drawnEndMin) } else { laneEnds[lane] = segment.drawnEndMin }
            segments[index].lane = lane
            groupEnd = group.isEmpty ? segment.drawnEndMin : max(groupEnd, segment.drawnEndMin)
            group.append(index)
        }
        close()
        return segments
    }

    /// The free stretches between consecutive drawn boxes that last at least `minimum` minutes. Declined plans
    /// are not commitments, so they neither end nor interrupt free time.
    static func gaps(_ segments: [Segment], minimum: Int = labeledGapMinimum) -> [Gap] {
        let kept = segments.filter { !$0.block.declined }
        guard var reach = kept.first?.drawnEndMin else { return [] }
        var gaps: [Gap] = []
        for segment in kept.dropFirst() {
            if segment.startMin - reach >= minimum {
                gaps.append(Gap(startMin: reach, endMin: segment.startMin))
            }
            reach = max(reach, segment.drawnEndMin)
        }
        return gaps
    }

    /// Wall-clock minutes after local midnight at `date`.
    static func minute(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    /// True once a plan's end has passed.
    static func hasEnded(_ plan: Plan, now: Date) -> Bool {
        plan.endAt.map { $0 <= now } == true
    }

    /// Every day of the weeks holding the month of `anchor`, Monday first.
    static func monthGrid(_ anchor: Date, calendar: Calendar = .current) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: anchor) else { return [] }
        let first = PlannerCalendar.monday(of: month.start, calendar: calendar)
        let last = PlannerCalendar.monday(of: month.end.addingTimeInterval(-1), calendar: calendar)
        let count = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 7
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    /// The minute a Day grid scrolls to on opening: the hour 45 minutes before now or the next plan, pulled back to the
    /// start of a plan that spans it. When now is more than two hours outside the day's plans it opens at the plans;
    /// with no plans, 45 minutes before now, or `emptyHours.lowerBound` for another day.
    static func opening(_ segments: [Segment], nowMinute: Int?) -> Int {
        let starts = segments.map(\.startMin)
        let focus: Int
        if let nowMinute, let first = starts.min(), let last = segments.map(\.endMin).max() {
            let near = nowMinute >= first - 120 && nowMinute <= last + 120
            focus = near ? (segments.first { $0.endMin > nowMinute }.map { min($0.startMin, nowMinute) } ?? nowMinute) : first
        } else {
            focus = nowMinute ?? starts.min() ?? emptyHours.lowerBound * 60 + 45
        }
        var anchor = max(0, Int((Double(focus - 45) / 60).rounded(.down)) * 60)
        for segment in segments where segment.startMin < anchor && segment.endMin > anchor { anchor = segment.startMin }
        return anchor
    }

    /// The minute a Week grid scrolls to on opening: one hour before the week's earliest plan.
    static func weekOpening(_ columns: [[Segment]]) -> Int {
        guard let first = columns.flatMap({ $0 }).map(\.startMin).min() else { return emptyHours.lowerBound * 60 }
        return max(0, Int((Double(first - 60) / 60).rounded(.down)) * 60)
    }
}

/// A plan's own clock, for a plan planned in another zone than the device's.
enum PlanZone {
    /// "In New York: 9:00 AM – 10:00 AM EDT" when the plan's zone has a different UTC offset than `device` at its
    /// start; nil for a plan in the device's zone or with no zone.
    static func plannedClock(_ plan: Plan, device: TimeZone = .current) -> String? {
        guard let id = plan.timeZone, let zone = TimeZone(identifier: id), zone.secondsFromGMT(for: plan.startAt) != device.secondsFromGMT(for: plan.startAt) else { return nil }
        let city = (id.split(separator: "/").last.map(String.init) ?? id).replacingOccurrences(of: "_", with: " ")
        let style = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)
        let range = plan.endAt.map { "\(plan.startAt.formatted(style)) – \($0.formatted(style))" } ?? plan.startAt.formatted(style)
        return "In \(city): \(range) \(zone.abbreviation(for: plan.startAt) ?? id)"
    }
}
