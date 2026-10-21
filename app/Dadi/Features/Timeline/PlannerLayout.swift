import Foundation

/// The planner's pure logic, matching thaali's `planner/blocks.ts`: a day's
/// blocks as segments on a minute axis with side-by-side lanes for overlaps,
/// the open time between them, and what is now and next.
enum PlannerLayout {
    /// The least open time between two blocks that is drawn as a gap.
    static let gapMinimum = 10
    /// Hours the axis shows on a day with no blocks.
    static let emptyHours = 7..<22

    /// One block's part of one day, in minutes after local midnight, with its lane.
    struct Segment: Hashable, Identifiable {
        let block: PlannerBlock
        let startMin: Int
        let endMin: Int
        /// Lane among the blocks it overlaps, and how many lanes that group has.
        var lane = 0
        var lanes = 1

        var id: String { block.id }
    }

    /// Open time between two blocks, in minutes after local midnight.
    struct Gap: Hashable {
        let startMin: Int
        let endMin: Int
    }

    /// `day`'s part of every block that touches it, earliest first, with
    /// overlapping blocks in side-by-side lanes.
    static func segments(_ blocks: [PlannerBlock], on day: Date, calendar: Calendar = .current) -> [Segment] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        func minutes(_ date: Date) -> Int { Int((date.timeIntervalSince(dayStart) / 60).rounded()) }
        var segments = blocks
            .filter { $0.startAt < dayEnd && $0.endAt > dayStart }
            .map { Segment(block: $0, startMin: max(0, minutes($0.startAt)), endMin: min(1440, minutes($0.endAt))) }
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
            if lane == laneEnds.count { laneEnds.append(segment.endMin) } else { laneEnds[lane] = segment.endMin }
            segments[index].lane = lane
            groupEnd = group.isEmpty ? segment.endMin : max(groupEnd, segment.endMin)
            group.append(index)
        }
        close()
        return segments
    }

    /// The open stretches between consecutive segments that last at least
    /// `gapMinimum` minutes.
    static func gaps(_ segments: [Segment]) -> [Gap] {
        guard var reach = segments.first?.endMin else { return [] }
        var gaps: [Gap] = []
        for segment in segments.dropFirst() {
            if segment.startMin - reach >= gapMinimum {
                gaps.append(Gap(startMin: reach, endMin: segment.startMin))
            }
            reach = max(reach, segment.endMin)
        }
        return gaps
    }

    /// The whole hours the axis spans: the segments' extent, or a default window.
    static func hours(_ segments: [Segment]) -> Range<Int> {
        guard let first = segments.map(\.startMin).min(), let last = segments.map(\.endMin).max() else { return emptyHours }
        return (first / 60)..<Int((Double(last) / 60).rounded(.up))
    }

    /// The segment happening at `nowMin` and the first one starting after it.
    static func nowAndNext(_ segments: [Segment], at nowMin: Int) -> (current: Segment?, next: Segment?) {
        (segments.first { $0.startMin <= nowMin && nowMin < $0.endMin }, segments.first { $0.startMin > nowMin })
    }

    /// True once a block was marked done or its time has passed.
    static func isSettled(_ block: PlannerBlock, now: Date) -> Bool {
        block.doneAt != nil || block.endAt <= now
    }

    /// Minutes as "1 h 20 min", "45 min", or "2 h".
    static func span(_ minutes: Int) -> String {
        let parts = [minutes / 60 > 0 ? "\(minutes / 60) h" : nil, minutes % 60 > 0 ? "\(minutes % 60) min" : nil].compactMap { $0 }
        return parts.isEmpty ? "0 min" : parts.joined(separator: " ")
    }
}
