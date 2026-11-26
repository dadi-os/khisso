import SwiftUI

/// A tile's task badge in plain type: how many tasks close that day with a late dot when one is past due, or a check
/// when all are done.
private struct MonthTaskBadge: View {
    let badge: MonthBadge

    var body: some View {
        if badge.closing > 0 {
            HStack(spacing: 2) {
                if badge.allDone {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.sageDeep)
                } else {
                    if badge.pastDue { Circle().fill(Color.lateDot).frame(width: 5, height: 5) }
                    Text("\(badge.closing)").font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(Color.inkMuted)
                }
            }
            .accessibilityLabel(badge.allDone ? "All tasks done" : "\(badge.closing) \(badge.closing == 1 ? "task closes" : "tasks close")\(badge.pastDue ? ", one past due" : "")")
        }
    }
}

/// What the month pager decides without drawing.
enum MonthPaging {
    /// How many months either side of the current one the pager reaches.
    static let reach = 24

    /// The first day of every month the pager reaches, around the month holding `now`.
    static func months(around now: Date, calendar: Calendar = .current) -> [Date] {
        let current = first(of: now, calendar: calendar)
        return (-reach...reach).compactMap { calendar.date(byAdding: .month, value: $0, to: current) }
    }

    /// Local midnight of the first day of the month holding `date`.
    static func first(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }

    /// True when `day` belongs to `month`: its page draws it at full strength; the head and tail days of the
    /// neighbouring months are dimmed.
    static func isFocused(_ day: Date, in month: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, equalTo: month, toGranularity: .month)
    }

    /// What one read covers: the whole-week grids of `month` and both neighbours, so a swipe shows plans at once.
    static func window(of month: Date, calendar: Calendar = .current) -> (from: Date, to: Date)? {
        guard let before = calendar.date(byAdding: .month, value: -1, to: month), let after = calendar.date(byAdding: .month, value: 1, to: month),
              let from = PlannerLayout.monthGrid(before, calendar: calendar).first, let last = PlannerLayout.monthGrid(after, calendar: calendar).last,
              let to = calendar.date(byAdding: .day, value: 1, to: last) else { return nil }
        return (from, to)
    }
}

/// The months as a pager: one page to a month, swiped sideways with a snap or moved by the arrows, each page the whole
/// weeks that touch the month with the neighbouring months' head and tail days dimmed. Each day is a tile of its plans
/// as tinted pills with whole-word titles ("+N more" past two) and a small badge of the tasks closing that day; a tile,
/// dimmed or not, opens its day.
struct MonthView: View {
    let yaad: YaadClient
    let actions: PlannerActions
    let online: Bool
    /// Shows `day` in the Day view.
    let openDay: (Date) -> Void

    /// Plans a tile lists before "+N more".
    static let tilePlans = 2

    @Environment(LiveData.self) private var live: LiveData?
    @State private var month: Date? = MonthPaging.first(of: .now)
    @State private var plans: [Plan] = []
    @State private var lists: [String: [PlanTask]] = [:]
    @State private var loaded = false
    @State private var error: String?
    @State private var readAt: Date?
    @State private var retries = 0

    private var focus: Date { month ?? MonthPaging.first(of: .now) }

    var body: some View {
        VStack(spacing: 10) {
            PeriodBar(title: focus.formatted(.dateTime.month(.wide).year()), summary: loaded ? PlanTime.periodSummary(actions.shown(plans), days: PlannerLayout.monthGrid(focus).filter { MonthPaging.isFocused($0, in: focus) }, noun: "month") : nil, previousLabel: "Previous month", nextLabel: "Next month", previous: { move(by: -1) }, next: { move(by: 1) }, current: { jump(to: MonthPaging.first(of: .now)) })
                .padding(.horizontal, 12)
            if loaded { FeedBanner(online: online, error: error, readAt: readAt).padding(.horizontal, 12) }
            if !loaded && error == nil {
                MonthSkeleton().padding(.horizontal, 12).frame(maxHeight: .infinity, alignment: .top)
            } else if !loaded, let error {
                ErrorCard(service: "Yaad", status: nil, message: error) { retries += 1 }.padding(.horizontal, 12).frame(maxHeight: .infinity, alignment: .top)
            } else {
                pager.opacity(online ? 1 : 0.6)
            }
        }
        .task(id: PeriodReload(start: focus, change: live?.yaad ?? 0, retry: retries)) { await load() }
        .sensoryFeedback(.selection, trigger: month)
    }

    private func move(by months: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: months, to: focus) else { return }
        jump(to: next)
    }

    private func jump(to next: Date) {
        guard next != month else { return }
        withAnimation(Motion.settle) { month = next }
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(MonthPaging.months(around: .now), id: \.self) { first in
                    page(of: first)
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $month)
    }

    /// One month's page: the weekday row over the whole-week grid, its tiles sharing the page's height.
    private func page(of first: Date) -> some View {
        let days = PlannerLayout.monthGrid(first)
        let shown = actions.shown(plans)
        let now = Date.now
        let rows = days.count / 7
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Array(days.prefix(7)), id: \.self) { day in
                    Text(day, format: .dateTime.weekday(.abbreviated)).font(.caption2.weight(.semibold)).foregroundStyle(.inkMuted).frame(maxWidth: .infinity)
                }
            }
            GeometryReader { proxy in
                let tile = max(Self.minimumTile, (proxy.size.height - CGFloat(rows - 1) * 4) / CGFloat(rows))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(days, id: \.self) { day in
                        tileView(day, month: first, height: tile, plans: shown, now: now)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    /// The least height of a tile, so its day and two plans always fit.
    static let minimumTile: CGFloat = 72

    private func tileView(_ day: Date, month: Date, height: CGFloat, plans: [Plan], now: Date) -> some View {
        let today = Calendar.current.isDate(day, inSameDayAs: now)
        let inMonth = MonthPaging.isFocused(day, in: month)
        let (shown, more) = PlanFilter.monthTile(plans, day: day, limit: Self.tilePlans)
        let badge = lists[TaskLogic.key(day)].map { TaskLogic.monthBadge(actions.ticker.shown($0), on: day) }
        return VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    Text(day, format: .dateTime.day())
                        .font(.caption.weight(today ? .bold : .semibold).monospacedDigit())
                        .foregroundStyle(today ? Color.sageDeep : .ink)
                    Spacer(minLength: 0)
                    if let badge { MonthTaskBadge(badge: badge) }
                }
                ForEach(shown) { plan in
                    if PlanFilter.runsAsBar(plan) {
                        let edge = PlanFilter.barEdges(plan, day: day)
                        let look = BarLook(plan)
                        let shape = UnevenRoundedRectangle(topLeadingRadius: edge.before ? 0 : 5, bottomLeadingRadius: edge.before ? 0 : 5, bottomTrailingRadius: edge.after ? 0 : 5, topTrailingRadius: edge.after ? 0 : 5, style: .continuous)
                        Text(plan.title)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(look.ink)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .frame(maxWidth: .infinity, minHeight: 15, alignment: .leading)
                            .background(look.fill, in: shape)
                            .overlay { shape.strokeBorder(look.line, style: StrokeStyle(lineWidth: 0.75, dash: look.dashed ? [3, 2] : [])) }
                            .padding(.leading, edge.before ? -4 : 0)
                            .padding(.trailing, edge.after ? -4 : 0)
                            .accessibilityLabel(plan.title)
                    } else {
                        HStack(alignment: .top, spacing: 3) {
                            Circle().fill(plan.tone).frame(width: 4, height: 4).padding(.top, 3)
                            Text(plan.title)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(plan.declined ? Color.inkMuted : .ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(plan.declined ? 0.6 : 1)
                        .accessibilityLabel(plan.title)
                    }
                }
                if more > 0 {
                    Button { actions.sheet = .day(day) } label: {
                        Text("+\(more) more").font(.system(size: 10, weight: .medium)).foregroundStyle(.inkMuted).frame(maxWidth: .infinity, minHeight: 24, alignment: .leading).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(more) more on \(day.formatted(.dateTime.weekday(.wide).month().day()))")
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .background(today ? Color.boneRaised : Color.boneRaised.opacity(0.5), in: .rect(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(today ? Color.sageDeep : .rule, lineWidth: today ? 1.5 : 1) }
            .opacity(inMonth ? 1 : 0.4)
            .contentShape(.rect)
            .onTapGesture { openDay(day) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Show \(day.formatted(.dateTime.weekday(.wide).month().day()))")
            .accessibilityAddTraits(.isButton)
    }

    private func load() async {
        let days = PlannerLayout.monthGrid(focus)
        guard let window = MonthPaging.window(of: focus) else { return }
        do {
            async let monthly = yaad.plans(from: window.from, to: window.to)
            async let tasks = yaad.taskLists(for: days)
            let (fetched, t) = try await (monthly, tasks)
            actions.settle(fetched)
            actions.ticker.settle()
            withAnimation(Motion.settle) {
                plans = fetched
                lists.merge(t) { _, new in new }
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
