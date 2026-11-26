import SwiftUI

/// The Planner widget: today's timed plans on a time column and spine. All of them when they fit; otherwise a window
/// that follows the day, grown from the plan on now (else the next, else the last), with quiet "N earlier" and "N
/// later" text, never a scroll. Each row carries a fact on the line under its title ("54 min · Engineering Building
/// room 1345"); the plan on now fills sage with a live progress hairline, the gap between plans reads "Free · 40 min",
/// and a footer counts today's tasks checked. After the last plan the same window shows its ended plans muted over a
/// footer of plans done, attended and tasks. An empty day shows the shared empty state over the task footer, which is
/// left out only when there are no tasks today or overdue. A long press on a
/// plan opens its actions; a tap on the tile opens the Day view.
struct PlannerWidget: View {
    let yaad: YaadClient
    let actions: PlannerActions
    /// False while dadi is out of reach: the tile shows the last answer.
    let online: Bool
    /// Opens the Day view.
    let open: () -> Void

    /// Height of the footer and the gap above it.
    private static let footer: CGFloat = 38
    /// Width of the time column.
    private static let timeColumn: CGFloat = 68

    @Environment(LiveData.self) private var live: LiveData?
    @State private var plans: [Plan] = []
    @State private var tasks: [PlanTask] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var readAt: Date?
    @State private var retries = 0

    var body: some View {
        let today = Calendar.current.startOfDay(for: .now)
        let shown = WidgetLogic.tilePlans(actions.shown(plans), on: today)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Planner").font(.headline).foregroundStyle(.sageText)
                Spacer()
                if loaded {
                    Text("\(shown.count) \(shown.count == 1 ? "plan" : "plans") today").font(.footnote).foregroundStyle(.inkMuted)
                }
            }
            content(shown, today: today)
                .opacity(online ? 1 : 0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.boneRaised, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.rule, lineWidth: 1))
        .contentShape(.rect(cornerRadius: 22))
        .onTapGesture(perform: open)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open today", open)
        .task(id: Reload(change: live?.yaad ?? 0, retry: retries)) { await load() }
    }

    @ViewBuilder
    private func content(_ shown: [Plan], today: Date) -> some View {
        if !loaded && error == nil {
            SkeletonRows(count: 4, height: WidgetLogic.planHeight)
        } else if !loaded, let error {
            ErrorCard(service: "Yaad", status: nil, message: error) { retries += 1 }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                FeedBanner(online: online, error: error, readAt: readAt)
                if shown.isEmpty {
                    let progress = TaskLogic.progress(TaskLogic.groups(actions.ticker.shown(tasks), on: .now))
                    EmptyState(title: "No plans today", detail: "Plans appear here as agents schedule them.")
                        .frame(maxHeight: .infinity)
                    if progress.total > 0 { footer(progress: progress, over: false, plans: []) }
                } else {
                    GeometryReader { proxy in
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            windowBody(shown, now: context.date, capacity: max(WidgetLogic.planHeight, proxy.size.height - Self.footer))
                        }
                    }
                }
            }
        }
    }

    private func windowBody(_ shown: [Plan], now: Date, capacity: CGFloat) -> some View {
        let window = WidgetLogic.window(shown, now: now, capacity: capacity)
        let progress = TaskLogic.progress(TaskLogic.groups(actions.ticker.shown(tasks), on: now))
        let over = WidgetLogic.dayOver(shown, now: now)
        let nextID = PlanTime.nextPlanID(shown, now: now)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: WidgetLogic.gap) {
                if window.earlier > 0 { remainder("\(window.earlier) earlier") }
                ForEach(Array(window.rows.enumerated()), id: \.offset) { _, row in
                    switch row {
                    case .free(let minutes):
                        HStack(spacing: 0) {
                            Color.clear.frame(width: Self.timeColumn)
                            spine(dot: nil)
                            Text("Free · \(Phrase.duration(TimeInterval(minutes) * 60))")
                                .font(.caption)
                                .foregroundStyle(.inkFaint)
                                .padding(.leading, 12)
                            Spacer(minLength: 0)
                        }
                        .frame(height: WidgetLogic.freeHeight)
                    case .plan(let plan, let current):
                        PlanRow(plan: plan, current: current, state: PlanTime.state(plan, now: now, nextID: nextID), now: now, timeColumn: Self.timeColumn, actions: actions)
                    }
                }
                if window.later > 0 { remainder("\(window.later) later") }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            footer(progress: progress, over: over, plans: shown)
        }
    }

    private func spine(dot: Color?) -> some View {
        ZStack {
            Rectangle().fill(Color.rule).frame(width: 1)
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
        }
        .frame(width: 12)
    }

    private func remainder(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.inkMuted)
            .frame(maxWidth: .infinity)
            .frame(height: WidgetLogic.chipHeight)
    }

    @ViewBuilder
    private func footer(progress: (done: Int, total: Int), over: Bool, plans: [Plan]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(over ? WidgetLogic.recap(plans, tasks: progress) : progress.total == 0 ? "No tasks today" : "\(progress.done) of \(progress.total) checked")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.inkMuted)
                .lineLimit(1)
            if !over {
                Capsule().fill(Color.rule).frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { bar in
                            Capsule()
                                .fill(progress.total > 0 && progress.done == progress.total ? Color.sageDeep : .sage)
                                .frame(width: progress.total == 0 ? 0 : bar.size.width * CGFloat(progress.done) / CGFloat(progress.total))
                        }
                    }
            }
        }
        .frame(height: Self.footer - 8, alignment: .bottom)
    }

    private func load() async {
        let today = Calendar.current.startOfDay(for: .now)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: today) else { return }
        do {
            async let fetched = yaad.plans(from: today, to: end)
            async let list = yaad.tasks(on: TaskLogic.key(today))
            let (p, t) = try await (fetched, list)
            actions.settle(p)
            plans = p
            tasks = t
            error = nil
            readAt = .now
            loaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private struct Reload: Hashable {
        let change: Int
        let retry: Int
    }
}

/// One plan of the widget: its start on the time column, a spine dot, its title and its fact; sage-filled with the
/// time left and a progress hairline while it is on, muted once ended or declined.
private struct PlanRow: View {
    let plan: Plan
    let current: Bool
    let state: TimeState
    let now: Date
    let timeColumn: CGFloat
    let actions: PlannerActions

    var body: some View {
        let end = plan.endAt ?? plan.startAt
        let look = PlanCardLook(plan, state: state)
        HStack(spacing: 0) {
            Text(Phrase.clock(plan.startAt))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: timeColumn - 8, alignment: .trailing)
                .padding(.trailing, 8)
            ZStack {
                Rectangle().fill(Color.rule).frame(width: 1)
                if look.check {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.sageDeep).padding(2).background(Color.slabAttended, in: .circle)
                } else {
                    Circle().fill(current ? Color.sageDeep : plan.tone).frame(width: 7, height: 7)
                }
            }
            .frame(width: 12)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(plan.title).font(.subheadline.weight(.semibold)).foregroundStyle(plan.declined || look.struck ? Color.inkMuted : .ink).strikethrough(look.struck).lineLimit(1)
                    if meetingLink(plan) != nil { Image(systemName: "video").font(.system(size: 10, weight: .semibold)).foregroundStyle(.inkFaint) }
                }
                Text(fact(end: end, caption: look.caption)).font(.caption.weight(look.check ? .semibold : .regular)).foregroundStyle(current || look.check ? Color.sageDeep : .inkMuted).lineLimit(1)
            }
            .padding(.leading, 12)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 8)
        .frame(height: current ? WidgetLogic.currentHeight : WidgetLogic.planHeight)
        .overlay(alignment: .bottomLeading) {
            if current && !look.check {
                let total = end.timeIntervalSince(plan.startAt)
                GeometryReader { bar in
                    Rectangle().fill(Color.sageDeep).frame(width: bar.size.width * min(1, max(0, now.timeIntervalSince(plan.startAt) / max(total, 1))), height: 2)
                }
                .frame(height: 2)
            }
        }
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .planCardSurface(rowLook(look), radius: 12)
        .contentShape(.rect)
        .contextMenu { PlanMenu(plan: plan, actions: actions) }
        .accessibilityElement(children: .combine)
    }

    /// Quiet rows (upcoming, past) draw no card: only a plan on now, attended, missed or declined has a surface.
    private func rowLook(_ look: PlanCardLook) -> PlanCardLook {
        switch PlanCardState.of(plan, state: state) {
        case .upcoming, .past: PlanCardLook.row(ended: state == .past)
        default: look
        }
    }

    /// "12 min left · Wells Hall room B115" while on, otherwise "54 min · Wells Hall room B115"; Declined in place of the
    /// duration for a plan Ankur declined, and Ankur's answer first once he gave one.
    private func fact(end: Date, caption: String?) -> String {
        let length = caption ?? (plan.declined ? "Declined" : current ? "\(Phrase.duration(end.timeIntervalSince(now))) left" : Phrase.duration(end.timeIntervalSince(plan.startAt)))
        let place = plan.place.map { place in place.room.map { "\(place.title) room \($0)" } ?? place.title }
        return [length, place].compactMap { $0 }.joined(separator: " · ")
    }
}
