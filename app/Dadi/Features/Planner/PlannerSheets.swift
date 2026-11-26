import SwiftUI

/// A task's sheet in the shared detail anatomy: its situation ("Past due by 5 days", "Closes Fri 11:59 PM · in 2
/// days"), then Opens, Closes, Done, Course, Owner and Last confirmed, and the actions Mark done and Message agent.
struct PlanTaskSheet: View {
    let task: PlanTask
    let actions: PlannerActions

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .padding(24)
    }

    private func content(now: Date) -> some View {
        let done = actions.ticker.isDone(task)
        let shown = task.marked(done: done)
        let status = PlanTime.taskStatus(shown, now: now)
        let agent = actions.agent(for: task.owner)
        let tone: SituationTone = switch status.tone {
        case .done: .live
        case .late: .late
        case .soon, .open: .wait
        case .none: .rest
        }
        return VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: task.title) { SituationLine(tone: tone, text: status.label, done: done) }
            VStack(spacing: 0) {
                if let opens = Self.opens(task) { FactRow(label: "Opens", value: opens) }
                if let close = task.closesAt { FactRow(label: "Closes", value: "\(close.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) \(Phrase.clock(close))", late: status.tone == .late) }
                if done { FactRow(label: "Done", value: "Yes") }
                if let hub = task.hub { FactRow(label: "Course", value: hub.title) }
                if let agent { FactRow(label: "Owner", value: actions.name(of: agent)) }
                if let seen = task.verifiedAt { FactRow(label: "Last confirmed", value: Phrase.agoPhrase(now.timeIntervalSince(seen))) }
            }
            ActionRail(items: [.action(title: done ? "Take back" : "Mark done", symbol: done ? "arrow.uturn.backward" : "checkmark.circle", emphasis: !done) {
                actions.ticker.tick(id: task.id, title: task.title, done: !done)
            }] + (agent == nil ? [] : [.action(title: "Message agent", symbol: "bubble.left") { actions.messageOwner(task.owner) }]))
            if let body = task.body, !body.isEmpty {
                InsetCard(title: "Notes") { Text(body).font(.callout).foregroundStyle(.ink) }
            }
        }
    }

    /// The date a task opens, from its YYYY-MM-DD, as "Fri, Nov 20".
    static func opens(_ task: PlanTask, calendar: Calendar = .current) -> String? {
        guard let key = task.opensOn, key.count == 10, let date = calendar.date(from: DateComponents(year: Int(key.prefix(4)), month: Int(key.dropFirst(5).prefix(2)), day: Int(key.suffix(2)))) else { return nil }
        return date.formatted(Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).month(.abbreviated).day())
    }
}

/// A day's card over Month: every plan and every task closing that day, each with its status in words.
struct DayCardSheet: View {
    let day: Date
    let yaad: YaadClient
    let actions: PlannerActions

    @State private var plans: [Plan] = []
    @State private var tasks: [PlanTask] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .padding(24)
        .task { await load() }
    }

    private func content(now: Date) -> some View {
        let shown = actions.shown(plans)
        let nextID = PlanTime.nextPlanID(shown, now: now)
        let closing = tasks.filter { $0.closesAt.map { Calendar.current.isDate($0, inSameDayAs: day) } == true }
        let open = actions.ticker.shown(tasks).filter { !$0.done }
        let summary = PlanTime.daySummary(shown, tasks: (open: open.count - open.filter(\.pastDue).count, pastDue: open.filter(\.pastDue).count))
        return VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: day.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                VStack(alignment: .leading, spacing: 2) {
                    let lines = loaded ? SummaryLines.split(summary) : ["Loading"]
                    SituationLine(tone: .rest, text: lines[0])
                    if lines.count > 1 { Text(lines[1]).font(.system(size: 13.5, weight: .medium)).foregroundStyle(.ink).padding(.leading, 15) }
                }
            }
            if let error, !loaded {
                Text(error).font(.footnote).foregroundStyle(.danger)
            }
            if loaded && shown.isEmpty && closing.isEmpty {
                Text("Nothing planned and nothing closing.").font(.subheadline).foregroundStyle(.inkMuted)
            }
            if !shown.isEmpty {
                InsetCard(title: "Plans", count: "\(shown.count)") {
                    ForEach(shown) { plan in
                        let state = PlanTime.state(plan, now: now, nextID: nextID)
                        Button { actions.sheet = .plan(plan) } label: {
                            row(title: plan.title, status: PlanTime.situation(plan, now: now, state: state), dot: plan.tone, muted: plan.declined || state == .past, dashed: plan.declined)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !closing.isEmpty {
                InsetCard(title: "Tasks closing", count: "\(closing.count)") {
                    ForEach(actions.ticker.shown(closing)) { task in
                        let status = PlanTime.taskStatus(task, now: now)
                        Button { actions.sheet = .task(task) } label: {
                            row(title: task.title, status: status.label, dot: status.tone == .late ? .lateDot : task.done ? .sageDeep : .inkFaint, muted: task.done, dashed: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(title: String, status: String, dot: Color, muted: Bool, dashed: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().strokeBorder(dot, style: StrokeStyle(lineWidth: dashed ? 1.5 : 0, dash: [2, 2])).background(Circle().fill(dashed ? .clear : dot)).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(muted ? Color.inkMuted : .ink).lineLimit(2).multilineTextAlignment(.leading)
                Text(status).font(.caption).foregroundStyle(.inkMuted).lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 40, alignment: .top)
        .contentShape(.rect)
    }

    private func load() async {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        do {
            async let p = yaad.plans(from: start, to: end)
            async let t = yaad.tasks(on: TaskLogic.key(start))
            let (fetchedPlans, fetchedTasks) = try await (p, t)
            plans = fetchedPlans.filter { PlanFilter.overlaps($0, day: start) }.sorted { $0.startAt < $1.startAt }
            tasks = fetchedTasks
            loaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Someday: "25 things with no time yet", as Tasks and Plans, identical titles grouped ("Gym training split ×12") in
/// the shared Expandable with their dates inside. A row names its keeper only when an agent keeps it and "checked 3d
/// ago" only from a day on.
struct SomedaySheet: View {
    let yaad: YaadClient
    let actions: PlannerActions

    @State private var tasks: [PlanTask] = []
    @State private var plans: [Plan] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var open: Set<String> = []

    /// How far ahead the loose plans are looked for.
    static let lookAheadDays = 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
        .padding(24)
        .task { await load() }
    }

    private func content(now: Date) -> some View {
        let openTasks = actions.ticker.placed(tasks).filter { !$0.done }
        let count = openTasks.count + plans.count
        return VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Someday") {
                SituationLine(tone: .rest, text: loaded ? "\(count) \(count == 1 ? "thing" : "things") with no time yet" : "Loading")
            }
            if let error, !loaded {
                Text(error).font(.footnote).foregroundStyle(.danger)
            } else if loaded && count == 0 {
                EmptyState(title: "Nothing someday", detail: "Things with no time yet appear here.")
            }
            if !openTasks.isEmpty {
                section("Tasks", count: openTasks.count) {
                    ForEach(TaskLogic.groupByTitle(openTasks)) { group in
                        grouped(group, prefix: "t") { task in taskRow(task, now: now) }
                    }
                }
            }
            if !plans.isEmpty {
                section("Plans", count: plans.count) {
                    ForEach(TaskLogic.groupByTitle(plans)) { group in
                        grouped(group, prefix: "p") { plan in planRow(plan, now: now) }
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.ink)
                Text("\(count)").font(.footnote).foregroundStyle(.inkMuted)
            }
            .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    @ViewBuilder
    private func grouped<T: Titled & Identifiable>(_ group: TitleGroup<T>, prefix: String, @ViewBuilder row: @escaping (T) -> some View) -> some View {
        if group.items.count == 1 {
            row(group.items[0])
        } else {
            let key = "\(prefix):\(group.id)"
            Expandable(isOpen: Binding(get: { open.contains(key) }, set: { if $0 { open.insert(key) } else { open.remove(key) } }), look: .row) {
                Text(group.label)
            } trailing: {
                Text("×\(group.items.count)")
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.items) { item in row(item) }
                }
            }
        }
    }

    private func taskRow(_ task: PlanTask, now: Date) -> some View {
        let keeper = PlanOwner.keptBy(task.owner)
        let meta = [keeper.map { actions.name(of: $0) }, TaskLogic.checkedAgo(task, now: now)].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 12) {
            Button { actions.ticker.tick(id: task.id, title: task.title, done: true) } label: { CheckCircle(done: actions.ticker.isDone(task)) }
                .buttonStyle(.plain)
                .accessibilityLabel("Check off \(task.title)")
            Button { actions.sheet = .task(task) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title).font(.callout).foregroundStyle(.ink).lineLimit(2).multilineTextAlignment(.leading)
                    if !meta.isEmpty { Text(meta).font(.caption).foregroundStyle(.inkMuted).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if actions.agent(for: task.owner) != nil {
                Button { actions.messageOwner(task.owner) } label: { Image(systemName: "bubble.left").font(.footnote).foregroundStyle(.inkMuted).frame(width: 36, height: 36) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Message agent")
            }
        }
        .frame(minHeight: 44)
    }

    private func planRow(_ plan: Plan, now: Date) -> some View {
        let keeper = PlanOwner.keptBy(plan.owner)
        let when = "\(plan.startAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(Phrase.clock(plan.startAt))"
        let meta = [when, keeper.map { actions.name(of: $0) }].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 12) {
            Button { actions.sheet = .plan(plan) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(plan.title).font(.callout).foregroundStyle(.ink).lineLimit(2).multilineTextAlignment(.leading)
                    Text(meta).font(.caption).foregroundStyle(.inkMuted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if actions.agent(for: plan.owner) != nil {
                Button { actions.messageOwner(plan.owner) } label: { Image(systemName: "bubble.left").font(.footnote).foregroundStyle(.inkMuted).frame(width: 36, height: 36) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Message agent")
            }
        }
        .frame(minHeight: 44)
        .padding(.leading, 2)
    }

    private func load() async {
        let today = Calendar.current.startOfDay(for: .now)
        guard let end = Calendar.current.date(byAdding: .day, value: Self.lookAheadDays, to: today) else { return }
        do {
            async let t = yaad.somedayTasks()
            async let p = yaad.plans(from: today, to: end)
            let (fetchedTasks, fetchedPlans) = try await (t, p)
            actions.ticker.settle()
            tasks = fetchedTasks
            plans = PlanFilter.loose(fetchedPlans)
            error = nil
            loaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
