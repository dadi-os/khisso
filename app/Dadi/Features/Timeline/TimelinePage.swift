import SwiftUI

/// The ways to look at the timeline, chosen from the page's name bubble or
/// its drawer.
enum TimelineMode: String, CaseIterable, Hashable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case someday = "Needs a time"

    var symbol: String {
        switch self {
        case .day: "clock"
        case .week: "calendar.day.timeline.left"
        case .month: "calendar"
        case .someday: "tray"
        }
    }
}

/// The timeline: Day (the hour axis, `PlannerDay`), Week (each day's
/// sessions and dues as rows with what is completed), Month (a calendar with
/// a dot on each busy day and the month's commitments) and Needs a time
/// (ideas, and tasks with a due but no time yet), with Someday under Week and
/// Month too. Every view is one of Yaad's timeline views; every session row
/// taps open its sheet, swipes right to Completed and left to message its
/// owner, and long-presses for its menu. Nothing here edits a plan: changes
/// go through the owner's thread or Dadi.
struct TimelinePage: View {
    let yaad: YaadClient
    @Binding var mode: TimelineMode

    @State private var actions: SessionActions

    /// - Parameters:
    ///   - mode: the view shown, which the name bubble and the drawer also set.
    ///   - message: opens the thread of the agent with this id.
    ///   - tellDadi: opens Talk to Dadi.
    init(yaad: YaadClient, mode: Binding<TimelineMode>, message: @escaping (String) -> Void, tellDadi: @escaping () -> Void) {
        self.yaad = yaad
        _mode = mode
        _actions = State(initialValue: SessionActions(yaad: yaad, message: message, tellDadi: tellDadi))
    }

    var body: some View {
        Group {
            switch mode {
            case .day:
                PlannerDay(yaad: yaad, actions: actions)
                    .transition(.opacity)
            case .week:
                WeekList(yaad: yaad, actions: actions)
                    .transition(.opacity)
            case .month:
                MonthList(yaad: yaad, actions: actions)
                    .transition(.opacity)
            case .someday:
                SomedayList(yaad: yaad, actions: actions)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            MarkBanner(actions: actions)
                .animation(Motion.settle, value: actions.undo)
                .animation(Motion.settle, value: actions.failure)
        }
        .sheet(item: Bindable(actions).opened) { item in
            SessionSheet(item: actions.shown(item), actions: actions)
                .fittedSheet()
                .presentationBackground(.thinMaterial)
        }
        .sensoryFeedback(.selection, trigger: mode)
        .navigationTitle("Timeline")
    }
}

/// Someday: ideas, and tasks with a due or an open but no time yet.
private struct SomedaySection: View {
    let items: [TimelineItem]
    let actions: SessionActions
    /// False where the page already names the section.
    var titled = true

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if titled {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Someday").font(.headline).foregroundStyle(.ink)
                        Spacer()
                        let needs = items.filter { $0.status != .idea }.count
                        if needs > 0 {
                            Text(needs == 1 ? "1 needs a time" : "\(needs) need a time")
                                .font(.footnote)
                                .foregroundStyle(.clay)
                        }
                    }
                }
                ForEach(actions.shown(items)) { item in
                    HStack {
                        Text(item.title).font(.subheadline.weight(.medium)).foregroundStyle(.ink)
                        Spacer(minLength: 8)
                        Text(somedayWhen(item))
                            .font(.caption)
                            .foregroundStyle(item.status == .idea ? Color.inkMuted : .clay)
                    }
                    .padding(14)
                    .background(.boneRaised.opacity(0.75), in: .rect(cornerRadius: 16, style: .continuous))
                    .sessionGestures(item, actions: actions, radius: 16)
                }
            }
        }
    }

    private func somedayWhen(_ item: TimelineItem) -> String {
        if item.status == .idea { return "Idea" }
        let day = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if let opens = item.opensAt { return "Opens \(opens.formatted(day))" }
        if let due = item.dueAt { return "By \(due.formatted(day))" }
        return "Needs a time"
    }
}

/// Needs a time on its own: every idea, and every task with a due or an
/// open but no time set aside, soonest due first. Dadi places them on the
/// week; a row's swipe left asks its owner.
private struct SomedayList: View {
    let yaad: YaadClient
    let actions: SessionActions

    /// How far ahead a due counts.
    private static let horizon = 120

    @Environment(LiveData.self) private var live
    @State private var items: [TimelineItem] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Dadi places these on your week before they're due.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .padding(.top, 8)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.danger)
                }
                if loaded && items.isEmpty && error == nil {
                    ContentUnavailableView("Nothing waiting", systemImage: "tray", description: Text("Ideas and tasks without a time show up here."))
                        .foregroundStyle(.inkMuted)
                        .padding(.top, 40)
                }
                SomedaySection(items: items, actions: actions, titled: false)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .animation(Motion.settle, value: items)
        }
        .refreshable { await load() }
        .task(id: live.yaad) { await load() }
    }

    private func load() async {
        let today = Calendar.current.startOfDay(for: .now)
        guard let end = Calendar.current.date(byAdding: .day, value: Self.horizon, to: today) else { return }
        do {
            let fetched = try await yaad.timeline(.someday, from: today, to: end)
            actions.settle(fetched)
            items = fetched.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

/// One session in a list: its time, title, and what became of it.
private struct SessionRow: View {
    let item: TimelineItem

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Group {
                if item.allDay {
                    Text("All day")
                } else if let start = item.startAt {
                    Text(start, format: .dateTime.hour().minute())
                } else if let due = item.dueAt {
                    Text(due, format: .dateTime.hour().minute())
                }
            }
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(.inkMuted)
            .lineLimit(1)
            .fixedSize()
            .frame(width: 66, alignment: .trailing)
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.ink)
                .strikethrough(item.cancelled, color: .inkFaint)
                .lineLimit(2)
            Spacer(minLength: 0)
            if let url = Directions.url(to: item.place), !item.completed {
                Button { openURL(url) } label: {
                    Image(systemName: "mappin.and.ellipse").font(.footnote.weight(.semibold)).foregroundStyle(.sageDeep)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Directions to \(item.place?.title ?? item.title)")
            }
            Text(mark)
                .font(.caption.weight(.bold))
                .foregroundStyle(item.missed || (item.startAt == nil && !item.completed) ? Color.clay : .inkMuted)
        }
        .padding(14)
        .background(item.startAt == nil ? Color.clay.opacity(0.08) : Color.boneRaised.opacity(0.75), in: .rect(cornerRadius: 16, style: .continuous))
        .opacity(item.completed || item.cancelled ? 0.55 : 1)
    }

    private var mark: String {
        if item.cancelled { return "Cancelled" }
        if item.completed { return "✓" }
        if item.missed { return "Missed" }
        return item.startAt == nil ? "Due" : ""
    }
}

/// The week from Monday: each day's sessions and dues, with how many of its
/// sessions are completed, then Someday. Swipe across a day heading or use
/// the arrows to move a week.
private struct WeekList: View {
    let yaad: YaadClient
    let actions: SessionActions

    @Environment(LiveData.self) private var live
    @State private var start = WeekList.monday(of: .now)
    @State private var items: [TimelineItem] = []
    @State private var someday: [TimelineItem] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { move(by: -1) } label: { Image(systemName: "chevron.left").frame(width: 20, height: 20) }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Previous week")
                    Spacer()
                    Text(title).font(.title3.weight(.semibold)).foregroundStyle(.ink).contentTransition(.opacity)
                    Spacer()
                    Button { move(by: 1) } label: { Image(systemName: "chevron.right").frame(width: 20, height: 20) }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Next week")
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.danger)
                }
                ForEach(days, id: \.self) { day in
                    let dayItems = actions.shown(items.filter { item in item.when.map { Calendar.current.isDate($0, inSameDayAs: day) } == true })
                    if !dayItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(heading(day)).font(.headline).foregroundStyle(Calendar.current.isDateInToday(day) ? Color.sageDeep : .ink)
                                Spacer()
                                let held = dayItems.filter { $0.startAt != nil && !$0.cancelled }
                                Text("\(held.filter(\.completed).count) of \(held.count)")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(.inkMuted)
                            }
                            ForEach(dayItems) { item in
                                SessionRow(item: item).sessionGestures(item, actions: actions, radius: 16)
                            }
                        }
                    }
                }
                SomedaySection(items: someday, actions: actions)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .animation(Motion.settle, value: items)
        }
        .refreshable { await load() }
        .sensoryFeedback(.selection, trigger: start)
        .task(id: WeekReload(start: start, change: live.yaad)) { await load() }
    }

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    private var title: String {
        guard let last = days.last else { return "" }
        let day = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(start.formatted(day)) – \(last.formatted(day))"
    }

    private func heading(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today · \(day.formatted(.dateTime.weekday(.wide).day()))" }
        return day.formatted(.dateTime.weekday(.wide).day())
    }

    private func move(by weeks: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: start) else { return }
        withAnimation(Motion.settle) {
            items = []
            start = next
        }
    }

    /// Monday at local midnight of the week holding `date`.
    static func monday(of date: Date) -> Date {
        let day = Calendar.current.startOfDay(for: date)
        let weekday = Calendar.current.component(.weekday, from: day)
        return Calendar.current.date(byAdding: .day, value: -((weekday + 5) % 7), to: day) ?? day
    }

    private func load() async {
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: start) else { return }
        do {
            async let planned = yaad.timeline(.planner, from: start, to: end)
            async let dues = yaad.timeline(.due, from: start, to: end)
            async let ideas = yaad.timeline(.someday, from: Calendar.current.startOfDay(for: .now), to: end)
            let (p, d, s) = try await (planned, dues, ideas)
            let fetched = (p + d).sorted { ($0.when ?? .distantFuture) < ($1.when ?? .distantFuture) }
            actions.settle(fetched + s)
            items = fetched
            someday = s
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// What makes the week read again: another week, or a change in Yaad.
private struct WeekReload: Hashable {
    let start: Date
    let change: Int
}

/// The month: a calendar with a dot on each day that has a commitment or a
/// due, then the month's commitments as rows, then Someday.
private struct MonthList: View {
    let yaad: YaadClient
    let actions: SessionActions

    @Environment(LiveData.self) private var live
    @State private var month = MonthList.first(of: .now)
    @State private var items: [TimelineItem] = []
    @State private var someday: [TimelineItem] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { move(by: -1) } label: { Image(systemName: "chevron.left").frame(width: 20, height: 20) }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Previous month")
                    Spacer()
                    Text(month, format: .dateTime.month(.wide).year())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.ink)
                        .contentTransition(.opacity)
                    Spacer()
                    Button { move(by: 1) } label: { Image(systemName: "chevron.right").frame(width: 20, height: 20) }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Next month")
                }
                calendar
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.danger)
                }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(actions.shown(items)) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                if let when = item.when {
                                    Text(when, format: .dateTime.month(.abbreviated).day())
                                        .font(.footnote.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(.inkMuted)
                                        .frame(width: 52, alignment: .leading)
                                }
                                SessionRow(item: item)
                            }
                            .sessionGestures(item, actions: actions, radius: 16)
                        }
                    }
                }
                SomedaySection(items: someday, actions: actions)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .animation(Motion.settle, value: items)
        }
        .refreshable { await load() }
        .sensoryFeedback(.selection, trigger: month)
        .task(id: MonthReload(month: month, change: live.yaad)) { await load() }
    }

    private var calendar: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let lead = (Calendar.current.component(.weekday, from: month) + 5) % 7
        let count = Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 0
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, name in
                Text(name).font(.caption2.weight(.semibold)).foregroundStyle(.inkFaint)
            }
            ForEach(0..<(lead + count), id: \.self) { index in
                if index < lead {
                    Color.clear.frame(height: 36)
                } else if let day = Calendar.current.date(byAdding: .day, value: index - lead, to: month) {
                    let busy = items.contains { $0.when.map { Calendar.current.isDate($0, inSameDayAs: day) } == true }
                    VStack(spacing: 3) {
                        Text(day, format: .dateTime.day())
                            .font(.subheadline.weight(Calendar.current.isDateInToday(day) ? .bold : .medium).monospacedDigit())
                            .foregroundStyle(Calendar.current.isDateInToday(day) ? Color.sageDeep : .ink)
                        Circle().fill(.clay).frame(width: 5, height: 5).opacity(busy ? 1 : 0)
                    }
                    .frame(height: 36)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func move(by months: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: months, to: month) else { return }
        withAnimation(Motion.settle) {
            items = []
            month = next
        }
    }

    /// Local midnight of the first day of the month holding `date`.
    static func first(of date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? Calendar.current.startOfDay(for: date)
    }

    private func load() async {
        guard let end = Calendar.current.date(byAdding: .month, value: 1, to: month) else { return }
        do {
            async let monthly = yaad.timeline(.month, from: month, to: end)
            async let ideas = yaad.timeline(.someday, from: Calendar.current.startOfDay(for: .now), to: end)
            let (m, s) = try await (monthly, ideas)
            actions.settle(m + s)
            items = m
            someday = s
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// What makes the month read again: another month, or a change in Yaad.
private struct MonthReload: Hashable {
    let month: Date
    let change: Int
}
