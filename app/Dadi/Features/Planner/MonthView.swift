import SwiftUI

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

    /// The day the agenda shows after the pager lands on `month`: `selected` while it lies in the month, else today
    /// when today does, else the month's first day.
    static func selection(keeping selected: Date, in month: Date, now: Date, calendar: Calendar = .current) -> Date {
        if isFocused(selected, in: month, calendar: calendar) { return selected }
        return calendar.startOfDay(for: isFocused(now, in: month, calendar: calendar) ? now : month)
    }
}

/// What a day of the month grid carries under its number: its plans (ahead or today, past, or past and all attended)
/// and whether a task closing that day is past due.
struct MonthMark: Equatable {
    enum Plans: Equatable { case none, ahead, past, attended }

    let plans: Plans
    let lateTask: Bool

    /// The mark of `day` from the plans Ankur keeps and the badge of the tasks closing that day.
    static func of(_ day: Date, plans: [Plan], badge: MonthBadge?, now: Date, calendar: Calendar = .current) -> MonthMark {
        let kept = PlanFilter.on(plans, day: day, calendar: calendar).filter { !$0.declined }
        let late = badge?.pastDue ?? false
        guard !kept.isEmpty else { return MonthMark(plans: .none, lateTask: late) }
        guard calendar.startOfDay(for: day) < calendar.startOfDay(for: now) else { return MonthMark(plans: .ahead, lateTask: late) }
        return MonthMark(plans: kept.allSatisfy { $0.attended == true } ? .attended : .past, lateTask: late)
    }
}

/// The month: a grid of day numbers (its name is the top bar's label) that pages sideways a month at a time, each day with a small mark
/// for its plans (ahead, past, attended) and a late dot for a past-due task, today ringed and the chosen day filled,
/// the neighbouring months' head and tail days faint. Under the grid the chosen day's agenda reads as the Day view's
/// rows, plans open their sheet and tasks tick; only the agenda scrolls. "Open day" shows the day in Day.
struct MonthView: View {
    let yaad: YaadClient
    let actions: PlannerActions
    let online: Bool
    /// Shows `day` in the Day view.
    let openDay: (Date) -> Void

    /// The height of one week of the grid; the pager holds six so the agenda never moves.
    static let weekHeight: CGFloat = 48

    @Environment(LiveData.self) private var live: LiveData?
    @State private var month: Date? = MonthPaging.first(of: .now)
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var plans: [Plan] = []
    @State private var lists: [String: [PlanTask]] = [:]
    @State private var loaded = false
    @State private var error: String?
    @State private var readAt: Date?
    @State private var retries = 0

    private var focus: Date { month ?? MonthPaging.first(of: .now) }

    var body: some View {
        VStack(spacing: 8) {
            if loaded { FeedBanner(online: online, error: error, readAt: readAt).padding(.horizontal, 20) }
            if !loaded && error == nil {
                MonthSkeleton().padding(.horizontal, 20).frame(maxHeight: .infinity, alignment: .top)
            } else if !loaded, let error {
                ErrorCard(service: "Yaad", status: nil, message: error) { retries += 1 }.padding(.horizontal, 20).frame(maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 0) {
                    weekdays
                    pager
                    agenda
                }
                .opacity(online ? 1 : 0.6)
            }
        }
        .preference(key: PlannerLabelKey.self, value: focus.formatted(.dateTime.month(.wide).year()))
        .task(id: PeriodReload(start: focus, change: live?.yaad ?? 0, retry: retries)) { await load() }
        .onChange(of: month) { _, next in
            if let next { selected = MonthPaging.selection(keeping: selected, in: next, now: .now) }
        }
        .sensoryFeedback(.selection, trigger: month)
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func choose(_ day: Date) {
        selected = Calendar.current.startOfDay(for: day)
        if !MonthPaging.isFocused(day, in: focus) { withAnimation(Motion.settle) { month = MonthPaging.first(of: day) } }
    }

    private var weekdays: some View {
        HStack(spacing: 0) {
            ForEach(Array(PlannerLayout.monthGrid(focus).prefix(7)), id: \.self) { day in
                Text(day, format: .dateTime.weekday(.abbreviated)).font(.caption2.weight(.semibold)).foregroundStyle(.inkFaint).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(MonthPaging.months(around: .now), id: \.self) { first in
                    grid(of: first).containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $month)
        .frame(height: 6 * Self.weekHeight)
    }

    private func grid(of first: Date) -> some View {
        let shown = actions.shown(plans)
        let now = Date.now
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(PlannerLayout.monthGrid(first), id: \.self) { day in
                cell(day, month: first, mark: MonthMark.of(day, plans: shown, badge: lists[TaskLogic.key(day)].map { TaskLogic.monthBadge(actions.ticker.shown($0), on: day) }, now: now))
            }
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func cell(_ day: Date, month: Date, mark: MonthMark) -> some View {
        let calendar = Calendar.current
        let chosen = calendar.isDate(day, inSameDayAs: selected)
        let today = calendar.isDateInToday(day)
        return Button { choose(day) } label: {
            VStack(spacing: 4) {
                Text(day, format: .dateTime.day())
                    .font(.system(size: 17, weight: chosen || today ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(chosen ? Color.bone : today ? .sageDeep : .ink)
                    .frame(width: 36, height: 36)
                    .background {
                        if chosen {
                            Circle().fill(Color.sageDeep)
                        } else if today {
                            Circle().strokeBorder(Color.sageDeep.opacity(0.55), lineWidth: 1.5)
                        }
                    }
                HStack(spacing: 2) {
                    if let tone = Self.tone(mark.plans) { Circle().fill(tone).frame(width: 5, height: 5) }
                    if mark.lateTask { Circle().fill(Color.lateDot).frame(width: 5, height: 5) }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: Self.weekHeight)
            .opacity(MonthPaging.isFocused(day, in: month) ? 1 : 0.38)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel((today ? "Today, " : "") + day.formatted(.dateTime.weekday(.wide).month().day()) + Self.words(mark))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private static func tone(_ plans: MonthMark.Plans) -> Color? {
        switch plans {
        case .none: nil
        case .ahead: .sage
        case .past: .inkFaint
        case .attended: .sageDeep
        }
    }

    private static func words(_ mark: MonthMark) -> String {
        let plans = switch mark.plans {
        case .none: ""
        case .ahead: ", has plans"
        case .past: ", had plans"
        case .attended: ", attended"
        }
        return plans + (mark.lateTask ? ", a task is past due" : "")
    }

    /// The chosen day: its name with "Open day" at the right, then its plans and the tasks closing that day.
    private var agenda: some View {
        let own = PlanFilter.agenda(actions.shown(plans), day: selected)
        let closing = (lists[TaskLogic.key(selected)] ?? []).filter { $0.closesAt.map { Calendar.current.isDate($0, inSameDayAs: selected) } == true }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selected, format: .dateTime.weekday(.wide).month(.wide).day()).font(.headline).foregroundStyle(.ink)
                Spacer()
                Button { openDay(selected) } label: {
                    Text("Open day").font(.subheadline.weight(.medium)).foregroundStyle(.sageDeep).frame(minHeight: 44).contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            ScrollView {
                if !own.isEmpty || !closing.isEmpty {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        rows(own, tasks: closing, now: context.date)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, 140, for: .scrollContent)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func rows(_ own: [Plan], tasks: [PlanTask], now: Date) -> some View {
        let today = Calendar.current.isDate(selected, inSameDayAs: now)
        let nextID = today ? PlanTime.nextPlanID(PlanFilter.grid(own), now: now) : nil
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: WidgetLogic.gap) {
                ForEach(own) { plan in
                    Button { actions.sheet = .plan(plan) } label: {
                        PlanRow(plan: plan, current: PlanFilter.isCurrent(plan, now: now), state: PlanTime.state(plan, now: now, nextID: nextID), now: now, timeColumn: 68, actions: actions)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !tasks.isEmpty {
                Text("Tasks").font(.caption.weight(.semibold)).foregroundStyle(.inkFaint).padding(.top, 16).padding(.bottom, 4)
                ForEach(tasks) { task in
                    ChecklistRow(task: task, done: actions.ticker.isDone(task), now: now) {
                        actions.ticker.tick(id: task.id, title: task.title, done: !actions.ticker.isDone(task))
                    } open: { actions.sheet = .task(task) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
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
