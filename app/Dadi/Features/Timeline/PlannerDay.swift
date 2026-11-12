import SwiftUI

/// One day of the timeline: the day's title (tap it for today), the week strip (`WeekStrip`, swiped
/// by weeks, a dot on each day with something due) and, today, what is happening now and next,
/// all pinned over the scrolling day, whose timed sessions (Yaad's planner view) on an hour axis, each
/// as tall as its time, with open time left as space and labeled with its length. Items due at a
/// time are not on the axis: the `DuePanel` pinned under the strip lists them all in its own scroll. Commitments are solid, the gym warm,
/// routines quiet, and a cancelled session is struck through. Each session's circle marks it
/// Completed (dashed once it has ended unmarked), the one happening now fills a bar as it runs,
/// and today's `NowLine` marks the time now. A session's other gestures are `SessionGestures`,
/// where a quick flick pages the day too; a drag across the empty day follows the finger a
/// little and moves a day once it goes far enough or is flung. The day is read again whenever
/// Yaad announces a change.
struct PlannerDay: View {
    let yaad: YaadClient
    let actions: SessionActions

    @Environment(LiveData.self) private var live
    @State private var day: Date
    @State private var blocks: [TimelineItem] = []
    @State private var due: [TimelineItem] = []
    @State private var error: String?
    @State private var direction: Edge = .trailing
    /// How far the day follows a sideways drag across its empty time.
    @State private var drift: CGFloat = 0
    /// The days of the shown week with something due.
    @State private var dueDays: Set<Date> = []
    /// Whether the Due panel is folded to its header.
    @State private var dueCollapsed = false
    /// The height of the page, of which the Due panel may take a third.
    @State private var pageHeight: CGFloat = 800

    /// Points per minute on the axis.
    private let scale: CGFloat = 1.3
    /// The shortest a session's box is drawn, the least a finger can hit.
    private static let minimumBlockHeight: CGFloat = 44

    /// - Parameter day: the day shown first; today by default.
    init(yaad: YaadClient, actions: SessionActions, day: Date = .now) {
        self.yaad = yaad
        self.actions = actions
        _day = State(initialValue: Calendar.current.startOfDay(for: day))
    }

    var body: some View {
        let segments = PlannerLayout.segments(actions.shown(blocks), on: day)
        axis(segments)
        .offset(x: drift)
        .contentShape(.rect)
        .gesture(
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
        .environment(\.pageDay, move(by:))
        .task(id: Reload(day: day, change: live.yaad)) { await load() }
        .task(id: Reload(day: Self.monday(of: day), change: live.yaad)) { await loadWeek() }
    }

    /// Monday at local midnight of the week holding `date`.
    nonisolated static func monday(of date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -((calendar.component(.weekday, from: start) + 5) % 7), to: start)!
    }

    /// The day's title over its date; tapping it jumps to today.
    private var header: some View {
        Button { go(to: .now) } label: {
            VStack(spacing: 1) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.ink)
                Text(day, format: .dateTime.month(.wide).day())
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
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
            blocks = []
            due = []
            day = next
        }
    }

    private func axis(_ segments: [PlannerLayout.Segment]) -> some View {
        let now = Calendar.current.component(.hour, from: .now) * 60 + Calendar.current.component(.minute, from: .now)
        let dues = PlannerLayout.dues(actions.shown(due), on: day)
        let spanned = PlannerLayout.hours(segments)
        let hours = Calendar.current.isDateInToday(day) ? min(spanned.lowerBound, now / 60)..<max(spanned.upperBound, now / 60 + 1) : spanned
        let origin = hours.lowerBound * 60
        let height = CGFloat(hours.count * 60) * scale
        let start = Calendar.current.isDateInToday(day) ? UnitPoint(x: 0, y: max(0, min(1, CGFloat(now - 60 - origin) / CGFloat(max(1, hours.count * 60))))) : .top
        return ScrollView {
            VStack(spacing: 14) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.danger)
                }
                GeometryReader { proxy in
                    let lane = proxy.size.width - 56
                    let heights = segments.map { max(Self.minimumBlockHeight, CGFloat($0.endMin - $0.startMin) * scale - 3) }
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(hours), id: \.self) { hour in
                            HStack(alignment: .top, spacing: 8) {
                                Text(hourLabel(hour))
                                    .font(.caption2.weight(.medium).monospacedDigit())
                                    .foregroundStyle(.inkFaint)
                                    .frame(width: 48, alignment: .trailing)
                                    .offset(y: -6)
                                Rectangle().fill(.rule).frame(height: 1)
                            }
                            .offset(y: CGFloat(hour * 60 - origin) * scale)
                        }
                        ForEach(PlannerLayout.gaps(segments).filter { $0.endMin - $0.startMin >= PlannerLayout.labeledGapMinimum }, id: \.self) { gap in
                            Text("\(PlannerLayout.span(gap.endMin - gap.startMin)) open")
                                .font(.caption2)
                                .foregroundStyle(.inkFaint)
                                .frame(width: lane, height: CGFloat(gap.endMin - gap.startMin) * scale)
                                .offset(x: 56, y: CGFloat(gap.startMin - origin) * scale)
                        }
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            let width = lane / CGFloat(segment.lanes)
                            let block = segment.block
                            BlockView(segment: segment, height: heights[index], toggle: actions.markable(block) ? { actions.toggle(block) } : nil)
                                .sessionGestures(block, actions: actions)
                                .frame(width: width - 4)
                                .offset(x: 56 + width * CGFloat(segment.lane), y: CGFloat(segment.startMin - origin) * scale + 1.5)
                        }
                        if Calendar.current.isDateInToday(day) {
                            NowLine(origin: origin, scale: scale, hours: hours)
                        }
                    }
                }
                .frame(height: height + 12)
                .padding(.top, 8)
                .padding(.bottom, 60)
                .id(day)
                .transition(.push(from: direction))
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .defaultScrollAnchor(start)
        .safeAreaInset(edge: .top, spacing: 8) {
            VStack(spacing: 10) {
                header
                WeekStrip(day: day, dueDays: dueDays, select: go(to:))
                if Calendar.current.isDateInToday(day) {
                    NowNext(segments: segments)
                }
                DuePanel(items: dues, available: pageHeight, collapsed: $dueCollapsed) { actions.opened = $0 }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .background(alignment: .top) {
                LinearGradient(stops: [.init(color: .bone, location: 0), .init(color: .bone, location: 0.8), .init(color: .bone.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                    .padding(.top, -200)
                    .allowsHitTesting(false)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
    }

    private func hourLabel(_ hour: Int) -> String {
        Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: day)?.formatted(.dateTime.hour()) ?? "\(hour)"
    }

    /// Reads which days of the shown week and its neighbors have something due, for the strip's dots.
    private func loadWeek() async {
        let monday = Self.monday(of: day)
        guard let from = Calendar.current.date(byAdding: .day, value: -7, to: monday), let end = Calendar.current.date(byAdding: .day, value: 14, to: monday) else { return }
        do {
            let dues = try await yaad.timeline(.due, from: from, to: end)
            dueDays = Set(dues.compactMap(\.dueAt).map(Calendar.current.startOfDay(for:)))
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func load() async {
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return }
        do {
            async let planned = yaad.timeline(.planner, from: day, to: end)
            async let dues = yaad.timeline(.due, from: day, to: end)
            let (fetched, fetchedDue) = try await (planned, dues)
            actions.settle(fetched + fetchedDue)
            if fetched != blocks || fetchedDue != due {
                withAnimation(Motion.settle) {
                    blocks = fetched
                    due = fetchedDue
                }
            }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// One session on the axis as an opaque sheet: its kind's dot, title and time, faded once it
/// is settled, struck through when cancelled or completed, with a pin that
/// opens directions when its place has an address and a circle that marks it
/// Completed: a check once it is, dashed once it has ended without a mark.
/// The session happening now fills a bar along its foot as it runs.
private struct BlockView: View {
    let segment: PlannerLayout.Segment
    let height: CGFloat
    /// Marks the session Completed or takes the mark back; nil when it cannot be marked.
    let toggle: (() -> Void)?

    @Environment(\.openURL) private var openURL

    var body: some View {
        let block = segment.block
        let settled = PlannerLayout.isSettled(block, now: .now)
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(block.tone)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.ink)
                    .strikethrough(block.cancelled || block.completed, color: .inkFaint)
                    .lineLimit(height > 50 ? 2 : 1)
                if height >= 44, let start = block.startAt, let end = block.endAt {
                    Text("\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.inkMuted)
                }
            }
            Spacer(minLength: 0)
            if !block.completed, let url = Directions.url(to: block.place) {
                Button { openURL(url) } label: {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.sageDeep)
                        .frame(width: 26, height: 26)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Directions to \(block.place?.title ?? block.title)")
            }
            if let toggle {
                Button(action: toggle) { mark(block) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(block.completed ? "Completed. Take the mark back" : "Mark \(block.title) completed")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, height >= 52 ? 8 : 5)
        .frame(height: height, alignment: .top)
        .overlay(alignment: .bottom) {
            if height > 40, let start = block.startAt, let end = block.endAt, !block.cancelled {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let total = end.timeIntervalSince(start)
                    let gone = context.date.timeIntervalSince(start)
                    if total > 0, gone > 0, gone < total {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.sageDeep.opacity(0.75))
                                .frame(width: proxy.size.width * gone / total)
                        }
                        .frame(height: 3)
                        .background(Color.sageDeep.opacity(0.12), in: .capsule)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                        .transition(.opacity)
                    }
                }
            }
        }
        .sessionSheet(radius: 12)
        .opacity(settled ? 0.55 : 1)
        .scaleEffect(block.completed ? 0.985 : 1)
        .animation(Motion.settle, value: block.completed)
        .accessibilityElement(children: .contain)
    }

    /// The Completed circle: a filled check once completed, a dashed ring once
    /// the session has ended unmarked, a plain ring before that.
    private func mark(_ block: TimelineItem) -> some View {
        let ended = block.endAt.map { $0 <= .now } == true
        return ZStack {
            if block.completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.sageDeep)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                Circle()
                    .strokeBorder(Color.sageDeep.opacity(ended ? 0.7 : 0.45), style: StrokeStyle(lineWidth: 1.5, dash: ended ? [2.5, 2.5] : []))
                    .frame(width: 17, height: 17)
                    .transition(.opacity)
            }
        }
        .frame(width: 26, height: 26)
        .contentShape(.circle)
        .animation(Motion.pop, value: block.completed)
    }
}

/// What's happening now and what's next, on today only.
private struct NowNext: View {
    let segments: [PlannerLayout.Segment]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let minute = Calendar.current.component(.hour, from: context.date) * 60 + Calendar.current.component(.minute, from: context.date)
            let (current, next) = PlannerLayout.nowAndNext(segments, at: minute)
            HStack(alignment: .top, spacing: 12) {
                part("NOW", title: current?.block.title ?? "Open time", detail: current?.block.endAt.map { "until \($0.formatted(date: .omitted, time: .shortened))" })
                Rectangle().fill(.rule).frame(width: 1)
                part("NEXT", title: next?.block.title ?? "Nothing else today", detail: next.map { "in \(PlannerLayout.span($0.startMin - minute))" })
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func part(_ label: String, title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.sageText)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.ink).lineLimit(2)
            if let detail { Text(detail).font(.caption).foregroundStyle(.inkMuted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What makes the planner read again: another day, or a change in Yaad.
private struct Reload: Hashable {
    let day: Date
    let change: Int
}
