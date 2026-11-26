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

/// The month as tiles, a week to a row: each day's plans as tinted pills with whole-word titles ("+N more" past two) and a small badge of the
/// tasks closing that day. A tile opens its day.
struct MonthView: View {
    let yaad: YaadClient
    let actions: PlannerActions
    let online: Bool
    /// Shows `day` in the Day view.
    let openDay: (Date) -> Void

    /// Plans a tile lists before "+N more".
    static let tilePlans = 2

    @Environment(LiveData.self) private var live: LiveData?
    @State private var month = MonthView.first(of: .now)
    @State private var plans: [Plan] = []
    @State private var lists: [String: [PlanTask]] = [:]
    @State private var loaded = false
    @State private var error: String?
    @State private var readAt: Date?
    @State private var retries = 0

    /// Local midnight of the first day of the month holding `date`.
    static func first(of date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)!.start
    }

    var body: some View {
        VStack(spacing: 10) {
            PeriodBar(title: month.formatted(.dateTime.month(.wide).year()), summary: loaded ? PlanTime.periodSummary(actions.shown(plans), days: PlannerLayout.monthGrid(month).filter { Calendar.current.isDate($0, equalTo: month, toGranularity: .month) }, noun: "month") : nil, previousLabel: "Previous month", nextLabel: "Next month", previous: { move(by: -1) }, next: { move(by: 1) }, current: { jump(to: Self.first(of: .now)) })
            if loaded { FeedBanner(online: online, error: error, readAt: readAt) }
            if !loaded && error == nil {
                MonthSkeleton().frame(maxHeight: .infinity, alignment: .top)
            } else if !loaded, let error {
                ErrorCard(service: "Yaad", status: nil, message: error) { retries += 1 }.frame(maxHeight: .infinity, alignment: .top)
            } else {
                grid.opacity(online ? 1 : 0.6)
            }
        }
        .padding(.horizontal, 12)
        .task(id: PeriodReload(start: month, change: live?.yaad ?? 0, retry: retries)) { await load() }
        .sensoryFeedback(.selection, trigger: month)
    }

    private func move(by months: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: months, to: month) else { return }
        jump(to: next)
    }

    private func jump(to next: Date) {
        guard next != month else { return }
        withAnimation(Motion.settle) {
            plans = []
            lists = [:]
            loaded = false
            error = nil
            month = next
        }
    }

    private var grid: some View {
        let days = PlannerLayout.monthGrid(month)
        let shown = actions.shown(plans)
        let now = Date.now
        return ScrollView {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(Array(days.prefix(7)), id: \.self) { day in
                        Text(day, format: .dateTime.weekday(.abbreviated)).font(.caption2.weight(.semibold)).foregroundStyle(.inkMuted).frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(days, id: \.self) { day in
                        tileView(day, plans: shown, now: now)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { retries += 1 }
    }

    private func tileView(_ day: Date, plans: [Plan], now: Date) -> some View {
        let today = Calendar.current.isDate(day, inSameDayAs: now)
        let inMonth = Calendar.current.isDate(day, equalTo: month, toGranularity: .month)
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
            .frame(maxWidth: .infinity, minHeight: 104, maxHeight: 104, alignment: .topLeading)
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
        let days = PlannerLayout.monthGrid(month)
        guard let first = days.first, let last = days.last, let end = Calendar.current.date(byAdding: .day, value: 1, to: last) else { return }
        do {
            async let monthly = yaad.plans(from: first, to: end)
            async let tasks = yaad.taskLists(for: days)
            let (fetched, t) = try await (monthly, tasks)
            actions.settle(fetched)
            actions.ticker.settle()
            withAnimation(Motion.settle) {
                plans = fetched
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
