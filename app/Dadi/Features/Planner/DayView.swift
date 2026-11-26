import SwiftUI
import UIKit

/// One day of the Planner: the day's title (tap it for today) over its date, the week strip, the
/// all-day band, and the full-height hour grid of the whole day, 12 AM to 12 AM, scrolling as a fixed layer with
/// the plans overlaid; the Checklist stands pinned under it as a panel with its own scroll. Today opens at the hour
/// 45 minutes before now or the next plan and carries the Now line, with a quiet "Now ↓" control when the line is
/// off screen. A drag across the empty day moves a day once it goes far enough. A plan taps open its sheet.
struct DayView: View {
    let yaad: YaadClient
    let actions: PlannerActions
    /// False while dadi is out of reach: what shows is the last answer.
    let online: Bool
    let scrollNow: Int

    @Environment(LiveData.self) private var live: LiveData?
    @State private var day: Date
    @State private var plans: [Plan] = []
    @State private var tasks: [PlanTask] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var readAt: Date?
    @State private var retries = 0
    @State private var direction: Edge = .trailing
    @State private var drift: CGFloat = 0
    @State private var position = ScrollPosition(y: 0)
    @State private var scroll = GridScroll()
    @State private var nudge = 0

    /// Points per minute on the axis: 56 pt an hour.
    static let scale: CGFloat = 56.0 / 60
    /// Width of the hour-label column.
    static let axisWidth: CGFloat = 64
    private static let topPad: CGFloat = 12
    private static let minimumBlock: CGFloat = 28

    /// What the grid's scroll reports: how far it has moved and how tall its window is.
    private struct GridScroll: Equatable {
        var offset: CGFloat = 0
        var height: CGFloat = 0
    }

    /// - Parameters:
    ///   - day: the day shown first; today by default.
    ///   - scrollNow: bumped to bring the day back to today, scrolled to now.
    init(yaad: YaadClient, actions: PlannerActions, online: Bool, day: Date = .now, scrollNow: Int = 0) {
        self.yaad = yaad
        self.actions = actions
        self.online = online
        _day = State(initialValue: Calendar.current.startOfDay(for: day))
        self.scrollNow = scrollNow
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                header
                WeekStrip(day: day, select: go(to:))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            timeline
                .frame(maxHeight: .infinity)
        }
        .task(id: Reload(day: day, change: live?.yaad ?? 0, retry: retries)) { await load() }
        .onChange(of: scrollNow) {
            go(to: .now)
            nudge += 1
        }
    }

    /// The day's title over its date; tapping it jumps to today.
    private var header: some View {
        Button { go(to: .now) } label: {
            VStack(spacing: 1) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.ink)
                Text(day, format: .dateTime.month(.wide).day()).font(.footnote).foregroundStyle(.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Jumps to today")
        .sensoryFeedback(.selection, trigger: day)
    }

    private var title: String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    private func move(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: day) else { return }
        go(to: next)
    }

    /// Shows `date`, sliding in from the side it lies on.
    private func go(to date: Date) {
        let next = Calendar.current.startOfDay(for: date)
        guard next != day else { return }
        direction = next > day ? .trailing : .leading
        withAnimation(Motion.settle) {
            plans = []
            tasks = []
            loaded = false
            error = nil
            day = next
        }
    }

    @ViewBuilder private var timeline: some View {
        if !loaded && error == nil {
            DayTimelineSkeleton().padding(.horizontal, 20).frame(maxHeight: .infinity, alignment: .top)
        } else if !loaded, let error {
            ErrorCard(service: "Yaad", status: nil, message: error) { retries += 1 }
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            VStack(spacing: 8) {
                FeedBanner(online: online, error: error, readAt: readAt).padding(.horizontal, 20)
                AllDayBand(days: [day], plans: PlanFilter.band(actions.shown(plans)), height: 32, axisWidth: Self.axisWidth, actions: actions)
                    .padding(.horizontal, 20)
                grid
                    .opacity(online ? 1 : 0.6)
                    .overlay {
                        if !plans.contains(where: { PlanFilter.overlaps($0, day: day) }) {
                            EmptyState(title: "No plans today", detail: "Plans appear here as agents schedule them.")
                                .padding(.vertical, 18)
                                .background(Color.bone.opacity(0.94), in: .rect(cornerRadius: 22, style: .continuous))
                                .padding(.horizontal, 20)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .offset(x: drift)
            .contentShape(.rect)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { drag in
                        guard abs(drag.translation.width) > abs(drag.translation.height) * 1.8 else { return }
                        drift = drag.translation.width * 0.22
                    }
                    .onEnded { drag in
                        let dx = drag.translation.width
                        let flung = abs(drag.predictedEndTranslation.width) > 160
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { drift = 0 }
                        guard abs(dx) > abs(drag.translation.height) * 1.8, abs(dx) > 70 || flung else { return }
                        move(by: dx < 0 ? 1 : -1)
                    }
            )
        }
    }

    /// The whole day's hour grid as its own scrolling layer, the plans overlaid on it.
    private var grid: some View {
        let shown = actions.shown(plans)
        let segments = PlannerLayout.segments(PlanFilter.grid(shown), on: day)
        let today = Calendar.current.isDateInToday(day)
        let height = 1440 * Self.scale + Self.topPad * 2
        let opening = PlannerLayout.opening(segments, nowMinute: today ? PlannerLayout.minute(of: .now) : nil)
        return ScrollView {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                canvas(segments, shown: shown, now: context.date, today: today)
            }
            .frame(height: height)
            .id(day)
            .transition(.push(from: direction))
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollPosition($position)
        .onScrollGeometryChange(for: GridScroll.self) { GridScroll(offset: $0.contentOffset.y, height: $0.containerSize.height) } action: { _, new in scroll = new }
        .task(id: Positioning(day: day, loaded: loaded, nudge: nudge)) {
            guard loaded else { return }
            try? await Task.sleep(for: .milliseconds(60))
            position.scrollTo(y: max(0, CGFloat(opening) * Self.scale + Self.topPad - 6))
        }
        .overlay { jump(today: today) }
        .refreshable { retries += 1 }
    }

    private struct Positioning: Hashable {
        let day: Date
        let loaded: Bool
        let nudge: Int
    }

    private func y(_ minute: Int) -> CGFloat { CGFloat(minute) * Self.scale + Self.topPad }

    private func canvas(_ segments: [PlannerLayout.Segment], shown: [Plan], now: Date, today: Bool) -> some View {
        let nextID = today ? PlanTime.nextPlanID(PlanFilter.grid(shown), now: now) : nil
        return GeometryReader { proxy in
            let lane = proxy.size.width - 40 - Self.axisWidth
            ZStack(alignment: .topLeading) {
                ForEach(0...24, id: \.self) { hour in
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(.rule).frame(height: 1).padding(.leading, Self.axisWidth - 4)
                        Text(hourLabel(hour))
                            .opacity(today && abs(CGFloat(hour * 60 - PlannerLayout.minute(of: now)) * Self.scale) < 28 ? 0 : 1)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.inkMuted)
                            .frame(width: Self.axisWidth - 10, alignment: .trailing)
                            .offset(y: -7)
                    }
                    .offset(y: y(hour * 60))
                }
                ForEach(PlannerLayout.gaps(segments), id: \.self) { gap in
                    Text("Free · \(Phrase.duration(TimeInterval(gap.endMin - gap.startMin) * 60))")
                        .font(.caption2)
                        .foregroundStyle(.inkFaint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(Color.bone.opacity(0.9), in: .capsule)
                        .frame(width: lane, height: CGFloat(gap.endMin - gap.startMin) * Self.scale)
                        .offset(x: Self.axisWidth, y: y(gap.startMin))
                        .allowsHitTesting(false)
                }
                if today {
                    NowLine(origin: 0, scale: Self.scale, axisWidth: Self.axisWidth, span: 1440, inset: Self.topPad)
                }
                ForEach(segments) { segment in
                    let width = lane / CGFloat(segment.lanes)
                    let state = PlanTime.state(segment.block, now: now, nextID: nextID)
                    BlockView(segment: segment, state: state, now: now, height: max(Self.minimumBlock, CGFloat(segment.drawnEndMin - segment.startMin) * Self.scale - 3), width: width - 8, actions: actions)
                        .frame(width: width - 8)
                        .offset(x: Self.axisWidth + width * CGFloat(segment.lane) + 4, y: y(segment.startMin) + 1.5)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// "Now ↓ 11:15 PM" when today's Now line is off screen.
    @ViewBuilder private func jump(today: Bool) -> some View {
        if today, scroll.height > 0 {
            let at = y(PlannerLayout.minute(of: .now))
            let below = at > scroll.offset + scroll.height - 12
            let above = at < scroll.offset + 12
            if below || above {
                Button {
                    withAnimation(Motion.settle) { position.scrollTo(y: max(0, at - scroll.height / 2)) }
                } label: {
                    Text("Now \(above ? "↑" : "↓") \(Phrase.clock(.now))")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.inkMuted)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color.bone.opacity(0.92), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: above ? .top : .bottom)
                .padding(10)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        "\(hour % 12 == 0 ? 12 : hour % 12) \(hour % 24 >= 12 ? "PM" : "AM")"
    }

    private func load() async {
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return }
        do {
            async let fetchedPlans = yaad.plans(from: day, to: end)
            async let fetchedTasks = yaad.tasks(on: TaskLogic.key(day))
            let (p, t) = try await (fetchedPlans, fetchedTasks)
            actions.settle(p)
            if p != plans || !loaded { withAnimation(Motion.settle) { plans = p } }
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
}

/// What makes the Day read again: another day, a change in Yaad, or a retry.
private struct Reload: Hashable {
    let day: Date
    let change: Int
    let retry: Int
}

/// One plan on the grid as a card. Under 58 pt it is one line (title and time); taller it adds the plan's situation
/// ("Now · 12 min left", "Ended 8 h ago · Attended") and then its place and room, its own clock when planned in
/// another zone, or "1 h 30 min long". The note is the sheet's. Past and declined plans are quiet, a declined one
/// dashed; the plan on now is sage-filled with a 2 pt hairline showing how much of it has gone.
private struct BlockView: View {
    let segment: PlannerLayout.Segment
    let state: TimeState
    let now: Date
    let height: CGFloat
    let width: CGFloat
    let actions: PlannerActions

    var body: some View {
        let plan = segment.block
        let look = PlanCardLook(plan, state: state)
        let compact = height < 58
        let narrow = segment.lanes > 1 || width < 120
        Button { actions.sheet = .plan(plan) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if look.check {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.sageDeep).frame(width: 7)
                    } else {
                        Circle().fill(plan.tone).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    }
                    Text(plan.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(plan.declined || look.struck ? Color.inkMuted : .ink)
                        .strikethrough(look.struck)
                        .lineLimit(TitleFit.lines(plan.title, width: width - 20 - 15, size: 13, weight: .semibold, maxLines: narrow ? max(1, Int((height - 8) / 17)) : compact ? 1 : 2))
                        .multilineTextAlignment(.leading)
                    if meetingLink(plan) != nil { Image(systemName: "video").font(.system(size: 10, weight: .semibold)).foregroundStyle(.inkFaint) }
                    Spacer(minLength: 0)
                    if !narrow, let end = plan.endAt, compact || height < 76 {
                        ViewThatFits(in: .horizontal) {
                            Text("\(Phrase.clock(plan.startAt)) – \(Phrase.clock(end))")
                            Text(Phrase.clock(plan.startAt))
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.inkMuted)
                        .lineLimit(1)
                    }
                }
                if !compact && !narrow {
                    Text(situation(plan)).font(.caption.weight(look.check ? .semibold : .regular)).foregroundStyle(look.check || state == .now ? Color.sageDeep : .inkMuted).lineLimit(1).padding(.leading, 15)
                    if let third = thirdLine(plan), height >= 78 {
                        Text(third).font(.caption).foregroundStyle(.inkMuted).lineLimit(1).padding(.leading, 15)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, compact ? 0 : 8)
            .frame(height: height, alignment: compact ? .leading : .topLeading)
            .overlay(alignment: .bottom) { if state == .now && !look.check { progress(plan) } }
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .planCardSurface(look, radius: 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu { PlanMenu(plan: plan, actions: actions) }
        .accessibilityLabel("\(plan.title), \(planWhen(plan)), \(PlanTime.situation(plan, now: now, state: state))")
    }

    /// The situation line: Ankur's answer first when he gave one ("Attended · Ended 8 h ago"), else the plan's own.
    private func situation(_ plan: Plan) -> String {
        guard let caption = PlanCardLook(plan, state: state).caption else { return PlanTime.situation(plan, now: now, state: state) }
        return "\(caption) · \(PlanTime.status(plan, now: now, state: state))"
    }

    private func progress(_ plan: Plan) -> some View {
        let total = (plan.endAt ?? plan.startAt).timeIntervalSince(plan.startAt)
        let fraction = total > 0 ? min(1, max(0, now.timeIntervalSince(plan.startAt) / total)) : 0
        return GeometryReader { proxy in
            Rectangle().fill(Color.sageDeep).frame(width: proxy.size.width * fraction)
        }
        .frame(height: 2)
    }

    private func thirdLine(_ plan: Plan) -> String? {
        if let place = plan.place { return place.room.map { "\(place.title) · room \($0)" } ?? place.title }
        if let own = PlanZone.plannedClock(plan) { return own }
        return plan.endAt.map { "\(Phrase.duration($0.timeIntervalSince(plan.startAt))) long" }
    }
}

/// The long-press menu every plan offers, here, in Week and in the widget: its details, Attended or Didn't attend
/// once it has started, Going or Not going (which opens the agent's chat), Message agent and Directions.
struct PlanMenu: View {
    let plan: Plan
    let actions: PlannerActions

    @Environment(\.openURL) private var openURL

    var body: some View {
        let now = Date.now
        let agent = actions.agent(for: plan.owner)
        Button { actions.sheet = .plan(plan) } label: { Label("Details", systemImage: "info.circle") }
        if !plan.declined, !plan.allDay, plan.startAt <= now {
            Button { actions.setAttended(plan.attended == true ? nil : true, on: plan) } label: { Label("Attended", systemImage: plan.attended == true ? "checkmark.circle.fill" : "checkmark.circle") }
            Button { actions.setAttended(plan.attended == false ? nil : false, on: plan) } label: { Label("Didn’t attend", systemImage: plan.attended == false ? "xmark.circle.fill" : "xmark.circle") }
        }
        if agent != nil, !(plan.endAt.map { $0 <= now } ?? false) {
            Button { actions.tell(plan, going: true) } label: { Label("Going", systemImage: "hand.thumbsup") }
            Button { actions.tell(plan, going: false) } label: { Label("Not going", systemImage: "hand.thumbsdown") }
        }
        if agent != nil {
            Button { actions.messageOwner(plan.owner) } label: { Label("Message agent", systemImage: "bubble.left") }
        }
        if let call = meetingLink(plan) {
            Button { openURL(call.url) } label: { Label("Join call", systemImage: "video") }
        }
        if let url = Directions.url(to: plan.place) {
            Button { openURL(url) } label: { Label("Directions", systemImage: "map") }
        }
    }
}
