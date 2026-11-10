import Foundation

/// The planner's pure logic, matching thaali's `planner/blocks.ts`: a day's
/// timed sessions as segments on a minute axis with side-by-side lanes for
/// overlaps, the open time between them, and what is now and next.
enum PlannerLayout {
    /// The least open time between two blocks that is drawn as a gap.
    static let gapMinimum = 10
    /// The least open time that is labeled with its length.
    static let labeledGapMinimum = 30
    /// The least minutes a block is drawn for, so a short session keeps the 44 pt tap height
    /// (44 pt at `PlannerDay.scale`, 1.3 pt per minute).
    static let minimumSpan = 34
    /// Hours the axis shows on a day with no blocks.
    static let emptyHours = 7..<22

    /// One block's part of one day, in wall-clock minutes after local midnight (7:30 AM is 450 on a
    /// 23-, 24- or 25-hour day alike), with its lane.
    struct Segment: Hashable, Identifiable {
        let block: TimelineItem
        let startMin: Int
        let endMin: Int
        /// Lane among the blocks it overlaps, and how many lanes that group has.
        var lane = 0
        var lanes = 1

        var id: String { block.id }

        /// Where the block's box ends on the axis: its own end, or its start plus `minimumSpan`.
        var drawnEndMin: Int { max(endMin, startMin + PlannerLayout.minimumSpan) }
    }

    /// Open time between two blocks, in minutes after local midnight.
    struct Gap: Hashable {
        let startMin: Int
        let endMin: Int
    }

    /// `day`'s part of every timed session that touches it, earliest first,
    /// with overlapping sessions in side-by-side lanes. The planner view only
    /// holds sessions with a start and an end.
    static func segments(_ blocks: [TimelineItem], on day: Date, calendar: Calendar = .current) -> [Segment] {
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
                guard let start = block.startAt, let end = block.endAt, start < dayEnd, end > dayStart else { return nil }
                return Segment(block: block, startMin: max(0, minutes(start)), endMin: min(1440, minutes(end)))
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

    /// The open stretches between consecutive drawn boxes that last at least
    /// `gapMinimum` minutes.
    static func gaps(_ segments: [Segment]) -> [Gap] {
        guard var reach = segments.first?.drawnEndMin else { return [] }
        var gaps: [Gap] = []
        for segment in segments.dropFirst() {
            if segment.startMin - reach >= gapMinimum {
                gaps.append(Gap(startMin: reach, endMin: segment.startMin))
            }
            reach = max(reach, segment.drawnEndMin)
        }
        return gaps
    }

    /// The whole hours the axis spans: the segments' extent, or a default window when there are none.
    static func hours(_ segments: [Segment]) -> Range<Int> {
        guard let first = segments.map(\.startMin).min(), let last = segments.map(\.endMin).max() else { return emptyHours }
        return (first / 60)..<Int((Double(last) / 60).rounded(.up))
    }

    /// Wall-clock minutes after local midnight at `date`.
    static func minute(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    /// The items due on `day` at a time: no start, a due time that day, and not hidden from the planner.
    static func dues(_ items: [TimelineItem], on day: Date, calendar: Calendar = .current) -> [TimelineItem] {
        items.filter { item in
            guard item.startAt == nil, !item.hideFromPlanner, let due = item.dueAt else { return false }
            return calendar.isDate(due, inSameDayAs: day)
        }
    }

    /// The segment happening at `nowMin` and the first one starting after it.
    static func nowAndNext(_ segments: [Segment], at nowMin: Int) -> (current: Segment?, next: Segment?) {
        (segments.first { $0.startMin <= nowMin && nowMin < $0.endMin }, segments.first { $0.startMin > nowMin })
    }

    /// True once a session was completed or cancelled, or its time has passed.
    static func isSettled(_ block: TimelineItem, now: Date) -> Bool {
        block.completed || block.cancelled || block.endAt.map { $0 <= now } == true
    }

    /// Minutes as "1 h 20 min", "45 min", or "2 h".
    static func span(_ minutes: Int) -> String {
        let parts = [minutes / 60 > 0 ? "\(minutes / 60) h" : nil, minutes % 60 > 0 ? "\(minutes % 60) min" : nil].compactMap { $0 }
        return parts.isEmpty ? "0 min" : parts.joined(separator: " ")
    }
}
