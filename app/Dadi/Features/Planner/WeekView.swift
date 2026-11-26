import SwiftUI

/// The arrows and title that move the Week or Month by a period; tapping the title returns to the current one, with one
/// true line about the period under it.
struct PeriodBar: View {
    let title: String
    let summary: String?
    let previousLabel: String
    let nextLabel: String
    let previous: () -> Void
    let next: () -> Void
    let current: () -> Void

    var body: some View {
        HStack {
            Button(action: previous) { Image(systemName: "chevron.left").frame(width: 20, height: 20) }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(previousLabel)
            Spacer()
            Button(action: current) {
                VStack(spacing: 1) {
                    Text(title).font(.title3.weight(.semibold)).foregroundStyle(.ink).contentTransition(.opacity)
                    if let summary {
                        ViewThatFits(in: .horizontal) {
                            Text(summary).lineLimit(1)
                            VStack(spacing: 0) { ForEach(summary.components(separatedBy: " · "), id: \.self) { Text($0) } }
                        }
                        .font(.caption)
                        .foregroundStyle(.inkFaint)
                        .multilineTextAlignment(.center)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: next) { Image(systemName: "chevron.right").frame(width: 20, height: 20) }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(nextLabel)
        }
    }
}

/// The week from Monday as the Day timesheet widened: three day columns in view in one horizontal scroll that pages
/// one day at a time, one shared vertical scroll, a sticky 64 pt hour axis on the left and a sticky header of one 36 pt line per
/// day on top (weekday, numeral, task dot and count; today a small filled pill, past days quiet; a tap opens Day).
/// There is no all-day rail: an all-day or multi-day plan is a hairline at the foot of that day's header, continuous
/// across joined days. The grid runs edge to edge at 64 pt an hour to the bottom of its container, opens one hour
/// before the week's earliest plan and never jumps.
struct WeekView: View {
    let yaad: YaadClient
    let actions: PlannerActions
    let online: Bool
    /// Shows `day` in the Day view.
    let openDay: (Date) -> Void

    @Environment(LiveData.self) private var live: LiveData?
    @State private var start = PlannerCalendar.monday(of: .now)
    @State private var plans: [Plan] = []
    @State private var lists: [String: [PlanTask]] = [:]
    @State private var loaded = false
    @State private var error: String?
    @State private var readAt: Date?
    @State private var retries = 0

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    private var title: String {
        guard let last = days.last else { return "" }
        let day = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(start.formatted(day)) – \(last.formatted(day))"
    }

    var body: some View {
        VStack(spacing: 8) {
            PeriodBar(title: title, summary: loaded ? PlanTime.periodSummary(actions.shown(plans), days: days, noun: "week") : nil, previousLabel: "Previous week", nextLabel: "Next week", previous: { move(by: -1) }, next: { move(by: 1) }, current: { jump(to: PlannerCalendar.monday(of: .now)) })
                .padding(.horizontal, 20)
            if !loaded && error == nil {
                WeekSkeleton().padding(.horizontal, 20).frame(maxHeight: .infinity, alignment: .top)
            } else if !loaded, let error {
                ErrorCard(service: "Yaad", status: nil, message: error) { retries += 1 }.padding(.horizontal, 20).frame(maxHeight: .infinity, alignment: .top)
            } else {
                FeedBanner(online: online, error: error, readAt: readAt).padding(.horizontal, 20)
                WeekBody(days: days, plans: actions.shown(plans), lists: lists, actions: actions, openDay: openDay)
                    .id(start)
                    .opacity(online ? 1 : 0.6)
            }
        }
        .task(id: PeriodReload(start: start, change: live?.yaad ?? 0, retry: retries)) { await load() }
        .sensoryFeedback(.selection, trigger: start)
    }

    private func move(by weeks: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: start) else { return }
        jump(to: next)
    }

    private func jump(to next: Date) {
        guard next != start else { return }
        withAnimation(Motion.settle) {
            plans = []
            lists = [:]
            loaded = false
            error = nil
            start = next
        }
    }

    private func load() async {
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: start) else { return }
        do {
            async let fetched = yaad.plans(from: start, to: end)
            async let tasks = yaad.taskLists(for: days)
            let (p, t) = try await (fetched, tasks)
            actions.settle(p)
            actions.ticker.settle()
            withAnimation(Motion.settle) {
                plans = p
                lists = t
            }
            error = nil
            readAt = .now
            loaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The week's horizontal paging: it settles on a whole day column, three of them in view.
private struct DayPaging: ScrollTargetBehavior {
    let column: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.origin.x = WeekMetrics.snappedOffset(target.rect.origin.x, column: column)
    }
}

/// What the week's horizontal scroll reports: how far it has moved.
private struct WeekScroll: Equatable {
    var offset: CGFloat = 0
}

/// The sticky header and grid of one week, made fresh for each week so its scroll positions start where they should:
/// the day columns on today (or the first day) and the hours on the hour before the earliest plan. Floating, with no
/// container and no vertical rules: bubbles and bridging all-day bars pinned over a grid that scrolls under them,
/// slab blocks, at most two lanes per overlap with "+N" for the rest, and a static now line.
private struct WeekBody: View {
    let days: [Date]
    let plans: [Plan]
    let lists: [String: [PlanTask]]
    let actions: PlannerActions
    let openDay: (Date) -> Void

    @State private var vertical: ScrollPosition
    @State private var horizontal = ScrollPosition(x: 0)
    @State private var scroll = WeekScroll()
    @State private var pageWidth: CGFloat = 390
    @State private var positioned = false
    private let clusters: [[WeekCluster]]
    private let lanes: [[(plan: Plan, columns: ClosedRange<Int>)]]

    private typealias M = WeekMetrics

    init(days: [Date], plans: [Plan], lists: [String: [PlanTask]], actions: PlannerActions, openDay: @escaping (Date) -> Void) {
        self.days = days
        self.plans = plans
        self.lists = lists
        self.actions = actions
        self.openDay = openDay
        let segments = days.map { PlannerLayout.segments(PlanFilter.grid(plans), on: $0, minimum: 26) }
        clusters = segments.map(WeekLayout.clusters)
        lanes = PlanFilter.spanLanes(plans, in: days)
        let thisWeek = days.contains { Calendar.current.isDateInToday($0) }
        let top = M.opening(starts: segments.flatMap { $0 }.map(\.startMin), nowMinute: thisWeek ? PlannerLayout.minute(of: .now) : nil)
        _vertical = State(initialValue: ScrollPosition(y: CGFloat(top) * M.scale))
    }

    private var column: CGFloat { M.column(pageWidth: pageWidth) }
    private var overflow: Bool { lanes.count > M.maxBarRows }
    private var header: CGFloat { M.headerHeight(rows: lanes.count, overflow: overflow) }
    private var gridHeight: CGFloat { 1440 * M.scale + M.bottomPad }

    var body: some View {
        let header = header
        ZStack(alignment: .top) {
            ScrollView {
                HStack(alignment: .top, spacing: M.gutter) {
                    axis
                    ScrollView(.horizontal) {
                        grid
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(DayPaging(column: column))
                    .scrollPosition($horizontal)
                    .onScrollGeometryChange(for: WeekScroll.self) { WeekScroll(offset: $0.contentOffset.x) } action: { _, new in scroll = new }
                }
                .padding(.top, header)
                .padding(.horizontal, M.cardPad)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($vertical)
            .mask {
                VStack(spacing: 0) {
                    Color.clear.frame(height: header - M.fade)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: M.fade)
                    Color.black
                }
            }
            pinned
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .task(id: pageWidth) {
            guard !positioned else { return }
            await Task.yield()
            positioned = true
            horizontal.scrollTo(x: M.offset(showing: days.firstIndex { Calendar.current.isDateInToday($0) } ?? 0, column: column))
        }
    }

    private func badge(_ day: Date, now: Date) -> DayBadge? {
        lists[TaskLogic.key(day)].map { TaskLogic.dayBadge(actions.ticker.shown($0), on: day, now: now) }
    }

    /// The bubbles, the bars and "+N more", floating over the grid and following its horizontal scroll.
    private var pinned: some View {
        let now = Date.now
        let column = column
        return HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: M.cardPad + M.axis + M.gutter, height: 1)
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: header)
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(days.enumerated()), id: \.element) { index, day in
                            bubble(day, now: now, column: column).frame(width: column).offset(x: column * CGFloat(index))
                        }
                        ForEach(Array(lanes.prefix(M.maxBarRows).enumerated()), id: \.offset) { row, lane in
                            ForEach(lane, id: \.plan.id) { entry in
                                bar(entry.plan, columns: entry.columns, column: column)
                                    .offset(x: column * CGFloat(entry.columns.lowerBound), y: M.headerTop + M.bubble + M.bubbleGap + CGFloat(row) * (M.barRow + M.barGap))
                            }
                        }
                    }
                    .frame(width: column * CGFloat(days.count), alignment: .topLeading)
                    .offset(x: -scroll.offset)
                }
                .clipped()
                .padding(.trailing, M.cardPad)
        }
        .overlay(alignment: .bottomTrailing) {
            if overflow, let first = lanes.dropFirst(M.maxBarRows).flatMap({ $0 }).map(\.columns.lowerBound).min() {
                let hidden = lanes.dropFirst(M.maxBarRows).reduce(0) { $0 + $1.count }
                Button { actions.sheet = .day(days[first]) } label: {
                    Text("+\(hidden) more").font(.system(size: 12)).foregroundStyle(.inkMuted).frame(height: M.moreRow).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.trailing, M.blockInset + M.cardPad)
                .padding(.bottom, M.headerBottom)
            }
        }
        .frame(height: header, alignment: .top)
    }

    private func bubble(_ day: Date, now: Date, column: CGFloat) -> some View {
        let today = Calendar.current.isDateInToday(day)
        let past = day < Calendar.current.startOfDay(for: now)
        let tasks = badge(day, now: now)
        let tier = M.tier(column: column)
        let ink: Color = today ? .todayInk : past ? .inkMuted : .ink
        let weekday = day.formatted(.dateTime.weekday(tier == .letter ? .narrow : .abbreviated)).uppercased()
        return Button { openDay(day) } label: {
            HStack(spacing: 6) {
                Text(weekday).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(today ? Color.todayInk : .inkMuted)
                Text(day, format: .dateTime.day()).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(ink)
                if let tasks, tasks.open > 0 || tasks.allDone {
                    HStack(spacing: 4) {
                        if tasks.open == 0 {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(today ? Color.todayInk : .sageDeep)
                        } else {
                            Circle().fill(tasks.urgent ? Color.lateDot : ink.opacity(0.6)).frame(width: 4, height: 4)
                            if tier == .full { Text("\(tasks.open)").font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(today ? Color.todayInk : .inkMuted) }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: M.bubble)
            .background {
                if today {
                    Capsule().fill(Color.today)
                } else {
                    Capsule().fill(Color.bone)
                    Capsule().fill(Color.sage.opacity(0.1))
                }
            }
            .shadow(color: .black.opacity(today ? 0 : 0.06), radius: 1, y: 1)
            .padding(.top, M.headerTop)
            .frame(width: column, height: M.headerTop + M.bubble + M.bubbleGap, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(day.formatted(.dateTime.weekday(.wide).month().day()))")
    }

    private func bar(_ plan: Plan, columns: ClosedRange<Int>, column: CGFloat) -> some View {
        let first = PlanFilter.barEdges(plan, day: days[columns.lowerBound])
        let last = PlanFilter.barEdges(plan, day: days[columns.upperBound])
        let look = BarLook(plan)
        let shape = UnevenRoundedRectangle(topLeadingRadius: first.before ? M.barSquare : M.barRadius, bottomLeadingRadius: first.before ? M.barSquare : M.barRadius, bottomTrailingRadius: last.after ? M.barSquare : M.barRadius, topTrailingRadius: last.after ? M.barSquare : M.barRadius, style: .continuous)
        return Button { actions.sheet = .plan(plan) } label: {
            Text(plan.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(look.ink)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(width: column * CGFloat(columns.count) - 2 * M.barMargin, height: M.barRow, alignment: .leading)
                .background { shape.fill(Color.bone); shape.fill(look.fill) }
                .overlay { shape.strokeBorder(look.line, style: StrokeStyle(lineWidth: 1, dash: look.dashed ? [4, 3] : [])) }
                .padding(.leading, M.barMargin)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PlanFilter.spanRange(plan).map { "\(plan.title), \($0)" } ?? plan.title)
    }

    private func y(_ minute: Int) -> CGFloat { CGFloat(minute) * M.scale }

    /// The hour labels, right-aligned in the 56 pt axis, which stay as the days scroll; the now pill sits in it, and a
    /// label within 28 pt of the line is hidden.
    private var axis: some View {
        let nowY = days.contains { Calendar.current.isDateInToday($0) } ? y(PlannerLayout.minute(of: .now)) : nil
        return ZStack(alignment: .topLeading) {
            ForEach(0...24, id: \.self) { hour in
                Text("\(hour % 12 == 0 ? 12 : hour % 12) \(hour % 24 >= 12 ? "PM" : "AM")")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.inkMuted)
                    .opacity(nowY.map { abs(y(hour * 60) - $0) < M.nowHides } == true ? 0 : 1)
                    .frame(width: M.axis, alignment: .trailing)
                    .offset(y: y(hour * 60) - 8)
            }
            if let nowY {
                Text(Date.now.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.bone)
                    .frame(width: M.nowPill.width, height: M.nowPill.height)
                    .background(Color.sageDeep, in: .capsule)
                    .offset(y: nowY - M.nowPill.height / 2)
            }
        }
        .frame(width: M.axis, height: gridHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var grid: some View {
        let column = column
        return TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            ZStack(alignment: .topLeading) {
                ForEach(0...24, id: \.self) { hour in
                    Rectangle().fill(Color.rule.opacity(0.7)).frame(height: 1).offset(y: y(hour * 60))
                }
                if days.contains(where: { Calendar.current.isDateInToday($0) }) {
                    let at = y(PlannerLayout.minute(of: now))
                    Rectangle().fill(Color.sageDeep.opacity(0.25)).frame(height: 2).offset(y: at - 1).allowsHitTesting(false)
                }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                        dayColumn(index, day: day, now: now, column: column)
                    }
                }
            }
            .frame(width: column * CGFloat(days.count), height: gridHeight, alignment: .topLeading)
        }
    }

    private func dayColumn(_ index: Int, day: Date, now: Date, column: CGFloat) -> some View {
        let today = Calendar.current.isDateInToday(day)
        let nextID = today ? PlanTime.nextPlanID(PlanFilter.grid(plans), now: now) : nil
        return ZStack(alignment: .topLeading) {
            if today {
                RoundedRectangle(cornerRadius: M.todayRadius, style: .continuous).fill(Color.sage.opacity(0.07))
            }
            if today {
                Rectangle().fill(Color.sageDeep).frame(height: 2).offset(y: y(PlannerLayout.minute(of: now)) - 1).allowsHitTesting(false)
            }
            ForEach(Array(clusters[index].enumerated()), id: \.offset) { _, cluster in
                ForEach(cluster.placed) { placed in
                    block(placed, state: PlanTime.state(placed.segment.block, now: now, nextID: nextID), column: column)
                }
                if !cluster.folded.isEmpty, let last = cluster.placed.max(by: { $0.segment.startMin < $1.segment.startMin }) {
                    let bottom = y(last.segment.startMin) + blockHeight(last.segment)
                    Button { actions.sheet = .day(day) } label: {
                        Text("+\(cluster.folded.count)").font(.system(size: 11)).foregroundStyle(.inkMuted).frame(minWidth: 28, minHeight: 24).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(cluster.folded.count) more: \(cluster.folded.map(\.title).joined(separator: ", "))")
                    .frame(width: column - 2 * M.blockInset, alignment: .trailing)
                    .offset(x: M.blockInset, y: bottom - 24)
                }
            }
        }
        .frame(width: column, height: gridHeight, alignment: .topLeading)
        .id(day)
    }

    private func blockHeight(_ segment: PlannerLayout.Segment) -> CGFloat {
        max(M.blockMinHeight, CGFloat(segment.drawnEndMin - segment.startMin) * M.scale - 4)
    }

    private func block(_ placed: WeekPlaced, state: TimeState, column: CGFloat) -> some View {
        let width = (column - 2 * M.blockInset - CGFloat(placed.lanes - 1) * M.laneGap) / CGFloat(placed.lanes)
        return WeekBlock(plan: placed.segment.block, state: state, width: width, height: blockHeight(placed.segment), lanes: placed.lanes, actions: actions)
            .frame(width: width)
            .offset(x: M.blockInset + CGFloat(placed.lane) * (width + M.laneGap), y: y(placed.segment.startMin) + M.blockTop)
    }
}

/// One plan in a week column, a floating slab: a tone dot (a check once attended) and a 13 pt title wrapped at whole words
/// on the lines that fit, with its 12 pt time under it when the slab is single-lane, wide and tall enough. The plan on now
/// takes the sage wash and border, an ended plan the past slab, a declined one a dashed outline, a missed one a struck title.
private struct WeekBlock: View {
    let plan: Plan
    let state: TimeState
    let width: CGFloat
    let height: CGFloat
    let lanes: Int
    let actions: PlannerActions

    private typealias M = WeekMetrics

    var body: some View {
        let narrow = lanes > 1 || width < 96
        let padX = narrow ? M.blockPadNarrow : M.blockPadWide
        let padY = height < M.timeLineMinHeight ? M.blockPadShort : M.blockPadY
        let timed = !narrow && height >= M.timeLineMinHeight
        let textWidth = width - 2 * padX - (narrow ? 0 : M.dot + M.dotGap)
        let lines = TitleFit.lines(plan.title, width: textWidth, size: 13, weight: .semibold, maxLines: max(1, Int((height - 2 * padY - (timed ? 16 : 0)) / 16)))
        let look = PlanCardLook(plan, state: state)
        let captioned = look.caption != nil && !narrow && height >= M.captionMinHeight
        Button { actions.sheet = .plan(plan) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: M.dotGap) {
                    if look.check {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.sageDeep).frame(height: 16)
                    } else if !narrow {
                        Circle().fill(plan.tone).frame(width: M.dot, height: M.dot).padding(.top, 5)
                    }
                    Text(plan.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(plan.declined || state == .past || look.struck ? Color.inkMuted : .ink)
                        .strikethrough(look.struck)
                        .lineLimit(lines)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }
                if timed, !narrow, meetingLink(plan) != nil {
                    Image(systemName: "video").font(.system(size: 10, weight: .semibold)).foregroundStyle(.inkFaint).padding(.leading, M.dot + M.dotGap)
                }
                if captioned, let caption = look.caption {
                    Text(caption).font(.system(size: 12, weight: .semibold)).foregroundStyle(look.check ? Color.sageDeep : .inkMuted).lineLimit(1).padding(.leading, look.check ? 20 : M.dot + M.dotGap)
                }
                if timed, let end = plan.endAt {
                    ViewThatFits(in: .horizontal) {
                        Text("\(Phrase.clock(plan.startAt)) – \(Phrase.clock(end))")
                        Text(Phrase.clock(plan.startAt))
                    }
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.inkMuted)
                    .lineLimit(1)
                    .padding(.leading, look.check ? 20 : M.dot + M.dotGap)
                }
            }
            .padding(.horizontal, padX)
            .padding(.vertical, padY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(height: height)
            .planCardSurface(look, radius: M.blockRadius)
            .shadow(color: .black.opacity(look.opacity < 1 ? 0 : 0.06), radius: 1, y: 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu { PlanMenu(plan: plan, actions: actions) }
        .accessibilityLabel("\(plan.title), \(planWhen(plan))")
    }
}
