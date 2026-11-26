import SwiftUI

/// The all-day band above Day's time axis: a 32 pt row per bar with a 4 pt gap, each tinted (tide for a course, sage
/// otherwise, dashed and muted when declined), titled in full and, for a plan that runs several days, showing its
/// span ("Nov 21 – 22") and open ‹ › edges where it continues past the day. Past two rows the rest fold behind "+N more".
struct AllDayBand: View {
    /// The days the band spans, aligned with the grid below: one for Day, seven for Week.
    let days: [Date]
    /// Plans for those days; only all-day and multi-day plans are drawn.
    let plans: [Plan]
    /// Bar height.
    let height: CGFloat
    /// Width of the hour-label column the bars start after.
    let axisWidth: CGFloat
    let actions: PlannerActions

    /// Rows the band shows before folding the rest.
    static let rows = 2
    private static let rowGap: CGFloat = 4
    private static let moreHeight: CGFloat = 24

    @State private var expandedHere = false

    private var expanded: Bool { expandedHere }

    var body: some View {
        let lanes = PlanFilter.spanLanes(plans, in: days)
        let shown = expanded ? lanes : Array(lanes.prefix(Self.rows))
        if !lanes.isEmpty {
            let more = lanes.count > Self.rows
            GeometryReader { proxy in
                let column = (proxy.size.width - axisWidth) / CGFloat(days.count)
                VStack(alignment: .leading, spacing: Self.rowGap) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { row, lane in
                        ZStack(alignment: .topLeading) {
                            Text(row == 0 ? "ALL DAY" : "")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(.inkMuted)
                                .frame(width: axisWidth - 8, height: height, alignment: .trailing)
                            ForEach(lane, id: \.plan.id) { entry in
                                bar(entry.plan, columns: entry.columns, width: column)
                                    .offset(x: axisWidth + column * CGFloat(entry.columns.lowerBound))
                            }
                        }
                        .frame(height: height, alignment: .topLeading)
                    }
                    if more {
                        Button { withAnimation(Motion.snap) { expandedHere.toggle() } } label: {
                            Text(expanded ? "Show fewer" : "+\(lanes.count - shown.count) more")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.inkMuted)
                                .padding(.horizontal, 10)
                                .frame(height: Self.moreHeight)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, axisWidth)
                    }
                }
            }
            .frame(height: CGFloat(shown.count) * height + CGFloat(shown.count - 1) * Self.rowGap + (more ? Self.rowGap + Self.moreHeight : 0))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("All-day plans")
        }
    }

    private func bar(_ plan: Plan, columns: ClosedRange<Int>, width: CGFloat) -> some View {
        let first = PlanFilter.barEdges(plan, day: days[columns.lowerBound])
        let last = PlanFilter.barEdges(plan, day: days[columns.upperBound])
        let look = BarLook(plan)
        let range = PlanFilter.spanRange(plan)
        let shape = UnevenRoundedRectangle(topLeadingRadius: first.before ? 3 : 10, bottomLeadingRadius: first.before ? 3 : 10, bottomTrailingRadius: last.after ? 3 : 10, topTrailingRadius: last.after ? 3 : 10, style: .continuous)
        return Button { actions.sheet = .plan(plan) } label: {
            HStack(spacing: 6) {
                if first.before { Text("‹") }
                Text(plan.title).lineLimit(1).layoutPriority(1)
                if let range {
                    Text(range).font(.caption).fontWeight(.regular).opacity(0.8).lineLimit(1)
                }
                Spacer(minLength: 0)
                if last.after { Text("›") }
            }
            .font(.system(size: height > 28 ? 13.5 : 11.5, weight: .semibold))
            .foregroundStyle(look.ink)
            .padding(.horizontal, height > 28 ? 12 : 6)
            .frame(width: width * CGFloat(columns.count) - 6, height: height, alignment: .leading)
            .background(look.fill, in: shape)
            .overlay { shape.strokeBorder(look.line, style: StrokeStyle(lineWidth: 1, dash: look.dashed ? [4, 3] : [])) }
            .padding(.leading, 3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu { PlanMenu(plan: plan, actions: actions) }
        .accessibilityLabel(range.map { "\(plan.title), \($0)" } ?? plan.title)
    }
}
