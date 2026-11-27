import SwiftUI

/// Every measure of the Week view, in points on a 4 pt base. Gaps come only from `gaps`; the tests keep it so.
enum WeekMetrics {
    static let cardPad: CGFloat = 12
    static let axis: CGFloat = 48
    static let gutter: CGFloat = 12
    static let headerTop: CGFloat = 4
    static let dayHead: CGFloat = 44
    static let bubbleGap: CGFloat = 8
    static let barRow: CGFloat = 32
    static let barGap: CGFloat = 4
    static let maxBarRows = 2
    static let moreRow: CGFloat = 24
    static let headerBottom: CGFloat = 12
    static let hour: CGFloat = 64
    static let bottomPad: CGFloat = 24
    static let blockInset: CGFloat = 8
    static let blockTop: CGFloat = 2
    static let laneGap: CGFloat = 4
    static let maxLanes = 2
    static let blockMinHeight: CGFloat = 28
    static let blockRadius: CGFloat = 11
    static let blockPadWide: CGFloat = 12
    static let blockPadNarrow: CGFloat = 4
    static let blockPadY: CGFloat = 8
    static let blockPadShort: CGFloat = 4
    static let timeLineMinHeight: CGFloat = 52
    static let captionMinHeight: CGFloat = 68
    static let barMargin: CGFloat = 8
    static let todayRadius: CGFloat = 16
    static let nowPill = CGSize(width: 48, height: 20)
    static let nowHides: CGFloat = 28
    static let fade: CGFloat = 24
    static let dot: CGFloat = 6
    static let dotGap: CGFloat = 8

    /// Every gap the view uses between things; each one is on the 4 pt base and from the system's table.
    static let gaps: [CGFloat] = [cardPad, gutter, headerTop, bubbleGap, barGap, headerBottom, blockInset, laneGap, bottomPad, fade, dotGap]
    /// The table every gap comes from.
    static let table: Set<CGFloat> = [4, 8, 12, 16, 24, 32]

    /// Points per minute.
    static var scale: CGFloat { hour / 60 }

    /// The pinned header's height: 4 top, the 44 day-heading row, then 8 and the bar rows (24 each, 4 between) when
    /// there are any, a 24 row for "+N more" 4 under them when bars overflow, and 12 above the first hour line.
    static func headerHeight(rows: Int, overflow: Bool) -> CGFloat {
        let shown = min(rows, maxBarRows)
        var height = headerTop + dayHead
        if shown > 0 { height += bubbleGap + CGFloat(shown) * barRow + CGFloat(shown - 1) * barGap }
        if overflow { height += barGap + moreRow }
        return height + headerBottom
    }

    /// The day columns the week shows, all at once.
    static let days = 7

    /// The width of one day column: the room beside the axis shared by the seven days, whole points.
    static func column(pageWidth: CGFloat) -> CGFloat {
        ((pageWidth - cardPad * 2 - axis - gutter) / CGFloat(days)).rounded(.down)
    }

    /// The minute at the top of the hours when the week opens: the hour before the earliest plan of the week, or before
    /// now when today is in the week and now is earlier; 6 AM for an empty week; never above midnight.
    static func opening(starts: [Int], nowMinute: Int?) -> Int {
        guard let first = starts.min() else { return 6 * 60 }
        let focus = nowMinute.map { min(first, $0) } ?? first
        return max(0, (focus - 60) / 60 * 60)
    }
}

/// One plan placed in a week column, with its lane among at most two.
struct WeekPlaced: Identifiable, Equatable {
    let segment: PlannerLayout.Segment
    let lane: Int
    let lanes: Int

    var id: String { segment.id }
}

/// A run of overlapping plans: up to two side by side, and the plans folded into "+N" past them.
struct WeekCluster: Equatable {
    let placed: [WeekPlaced]
    let folded: [Plan]
}

enum WeekLayout {
    /// A day's segments as clusters of overlapping plans with at most `WeekMetrics.maxLanes` lanes each; the third and
    /// further plans of a cluster are folded.
    static func clusters(_ segments: [PlannerLayout.Segment]) -> [WeekCluster] {
        var out: [WeekCluster] = []
        var group: [PlannerLayout.Segment] = []
        var groupEnd = 0
        func close() {
            guard !group.isEmpty else { return }
            let lanes = min(WeekMetrics.maxLanes, (group.map(\.lane).max() ?? 0) + 1)
            out.append(WeekCluster(
                placed: group.filter { $0.lane < WeekMetrics.maxLanes }.map { WeekPlaced(segment: $0, lane: $0.lane, lanes: lanes) },
                folded: group.filter { $0.lane >= WeekMetrics.maxLanes }.map(\.block)
            ))
            group = []
        }
        for segment in segments {
            if !group.isEmpty && segment.startMin >= groupEnd { close() }
            groupEnd = group.isEmpty ? segment.drawnEndMin : max(groupEnd, segment.drawnEndMin)
            group.append(segment)
        }
        close()
        return out
    }
}
