import SwiftUI

/// One day of the timeline: the week's days in a strip (a dot on each with
/// something due), what's happening now and next, what is due that day, then
/// the day's timed sessions (Yaad's planner view) on an hour axis, each as
/// tall as its time, with open time left as space and labeled with its
/// length. Commitments are solid, the gym warm, routines quiet, and a
/// cancelled session is struck through. Each session's circle marks it
/// Completed (dashed once it has ended unmarked), the one happening now
/// fills a bar as it runs, and the time now sits in the gutter on a line
/// that runs behind the sessions. A session's other gestures are
/// `SessionGestures`, where a quick flick pages the day too; a drag across
/// the empty day follows the finger a little and moves a day once it goes
/// far enough or is flung. The day is read again whenever Yaad announces a
/// change.
struct PlannerDay: View {
    let yaad: YaadClient
    let actions: SessionActions

    @Environment(LiveData.self) private var live
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var blocks: [TimelineItem] = []
    @State private var due: [TimelineItem] = []
    @State private var error: String?
    @State private var direction: Edge = .trailing
    /// How far the day follows a sideways drag across its empty time.
    @State private var drift: CGFloat = 0
    /// The days of the shown week with something due.
    @State private var dueDays: Set<Date> = []

    /// Points per minute on the axis.
    private let scale: CGFloat = 1.3

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

    /// The week holding `day` as a row of days to tap, today in sage, the
    /// shown day filled, a dot under each day with something due.
    private var weekStrip: some View {
        let monday = Self.monday(of: day)
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                if let date = Calendar.current.date(byAdding: .day, value: offset, to: monday) {
                    let shown = Calendar.current.isDate(date, inSameDayAs: day)
                    let today = Calendar.current.isDateInToday(date)
                    Button { go(to: date) } label: {
                        VStack(spacing: 3) {
                            Text(date, format: .dateTime.weekday(.narrow))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(shown ? Color.bone.opacity(0.8) : .inkFaint)
                            Text(date, format: .dateTime.day())
                                .font(.callout.weight(shown || today ? .bold : .medium).monospacedDigit())
                                .foregroundStyle(shown ? Color.bone : today ? .sageDeep : .ink)
                            Circle()
                                .fill(shown ? Color.bone : .clay)
                                .frame(width: 4, height: 4)
                                .opacity(dueDays.contains(Calendar.current.startOfDay(for: date)) ? 1 : 0)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if shown {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.sageDeep)
                            }
                        }
                        .contentShape(.rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month().day()))
                    .accessibilityAddTraits(shown ? .isSelected : [])
                }
            }
        }
        .animation(Motion.snap, value: day)
    }

    /// Monday at local midnight of the week holding `date`.
    static func monday(of date: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -((calendar.component(.weekday, from: start) + 5) % 7), to: start)!
    }

    private var header: some View {
        HStack {
            Button { move(by: -1) } label: { Image(systemName: "chevron.left").frame(width: 20, height: 20) }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Previous day")
            Spacer()
            VStack(spacing: 1) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.ink)
                Text(day, format: .dateTime.month(.wide).day())
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
            }
            .contentTransition(.opacity)
            .onTapGesture { withAnimation(Motion.settle) { day = Calendar.current.startOfDay(for: .now) } }
            Spacer()
            Button { move(by: 1) } label: { Image(systemName: "chevron.right").frame(width: 20, height: 20) }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Next day")
        }
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
        let spanned = PlannerLayout.hours(segments)
        let hours = Calendar.current.isDateInToday(day) ? min(spanned.lowerBound, now / 60)..<max(spanned.upperBound, now / 60 + 1) : spanned
        let origin = hours.lowerBound * 60
        let height = CGFloat(hours.count * 60) * scale
        let start = Calendar.current.isDateInToday(day) ? UnitPoint(x: 0, y: max(0, min(1, CGFloat(now - 60 - origin) / CGFloat(max(1, hours.count * 60))))) : .top
        return ScrollView {
            VStack(spacing: 14) {
                header
                weekStrip
                if Calendar.current.isDateInToday(day) {
                    NowNext(segments: segments)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.danger)
                }
                ForEach(actions.shown(due)) { item in
                    DueRow(item: item)
                        .sessionGestures(item, actions: actions, radius: 16)
                }
                GeometryReader { proxy in
                    let lane = proxy.size.width - 56
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
                        if Calendar.current.isDateInToday(day) {
                            NowLine(origin: origin, scale: scale, hours: hours)
                        }
                        ForEach(segments) { segment in
                            let width = lane / CGFloat(segment.lanes)
                            let block = segment.block
                            BlockView(segment: segment, height: max(30, CGFloat(segment.endMin - segment.startMin) * scale - 3), toggle: actions.markable(block) ? { actions.toggle(block) } : nil)
                                .sessionGestures(block, actions: actions)
                                .frame(width: width - 4)
                                .offset(x: 56 + width * CGFloat(segment.lane), y: CGFloat(segment.startMin - origin) * scale + 1.5)
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
        .defaultScrollAnchor(start)
    }

    private func hourLabel(_ hour: Int) -> String {
        Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: day)?.formatted(.dateTime.hour()) ?? "\(hour)"
    }

    /// Reads which days of the shown week have something due, for the strip's dots.
    private func loadWeek() async {
        let monday = Self.monday(of: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: monday) else { return }
        do {
            let dues = try await yaad.timeline(.due, from: monday, to: end)
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

/// How strongly a session stands out: commitments (and a session of no kind)
/// solid, the gym warm, other routines quiet, as in thaali.
private enum Tone {
    case solid, warm, quiet

    init(kind: PlanKind?) {
        switch kind {
        case .gym: self = .warm
        case .some(let kind) where kind.isRoutine: self = .quiet
        default: self = .solid
        }
    }

    var fill: Color {
        switch self {
        case .solid: .sage.opacity(0.24)
        case .warm: .clay.opacity(0.16)
        case .quiet: .boneRaised
        }
    }

    var edge: Color {
        switch self {
        case .solid: .sageLine
        case .warm: .clay.opacity(0.5)
        case .quiet: .rule
        }
    }

    var ink: Color {
        switch self {
        case .solid: .sageDeep
        case .warm: .clay
        case .quiet: .inkMuted
        }
    }
}

/// One session on the axis: its title and time, toned by kind, faded once it
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
        let tone = Tone(kind: block.kind)
        let settled = PlannerLayout.isSettled(block, now: .now)
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(block.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.ink)
                    .strikethrough(block.cancelled || block.completed, color: .inkFaint)
                    .lineLimit(height > 50 ? 2 : 1)
                if height > 44, let start = block.startAt, let end = block.endAt {
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
                        .foregroundStyle(tone.ink)
                        .frame(width: 26, height: 26)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Directions to \(block.place?.title ?? block.title)")
            }
            if let toggle {
                Button(action: toggle) { mark(block, tone: tone) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(block.completed ? "Completed. Take the mark back" : "Mark \(block.title) completed")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, height > 40 ? 8 : 5)
        .frame(height: height, alignment: .top)
        .overlay(alignment: .bottom) {
            if height > 40, let start = block.startAt, let end = block.endAt, !block.cancelled {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let total = end.timeIntervalSince(start)
                    let gone = context.date.timeIntervalSince(start)
                    if total > 0, gone > 0, gone < total {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(tone.ink.opacity(0.75))
                                .frame(width: proxy.size.width * gone / total)
                        }
                        .frame(height: 3)
                        .background(tone.ink.opacity(0.12), in: .capsule)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                        .transition(.opacity)
                    }
                }
            }
        }
        .background(tone.fill, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tone.edge, lineWidth: 1))
        .opacity(settled ? 0.55 : 1)
        .scaleEffect(block.completed ? 0.985 : 1)
        .animation(Motion.settle, value: block.completed)
        .accessibilityElement(children: .contain)
    }

    /// The Completed circle: a filled check once completed, a dashed ring once
    /// the session has ended unmarked, a plain ring before that.
    private func mark(_ block: TimelineItem, tone: Tone) -> some View {
        let ended = block.endAt.map { $0 <= .now } == true
        return ZStack {
            if block.completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tone.ink)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                Circle()
                    .strokeBorder(tone.ink.opacity(ended ? 0.7 : 0.45), style: StrokeStyle(lineWidth: 1.5, dash: ended ? [2.5, 2.5] : []))
                    .frame(width: 17, height: 17)
                    .transition(.opacity)
            }
        }
        .frame(width: 26, height: 26)
        .contentShape(.circle)
        .animation(Motion.pop, value: block.completed)
    }
}

/// A deadline on the day, above the axis: what is due and when.
private struct DueRow: View {
    let item: TimelineItem

    var body: some View {
        HStack(spacing: 10) {
            Text("Due")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(.clay)
            Text(item.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.ink)
                .strikethrough(item.completed, color: .inkFaint)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let due = item.dueAt, !item.allDay {
                Text(due, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.inkMuted)
            }
            if item.completed {
                Image(systemName: "checkmark.circle.fill").font(.footnote).foregroundStyle(.sageDeep)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.clay.opacity(0.1), in: .rect(cornerRadius: 16, style: .continuous))
        .opacity(item.completed ? 0.6 : 1)
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

/// The time now in a clay pill in the gutter, on a line across the axis at
/// the current minute that runs behind the sessions.
private struct NowLine: View {
    let origin: Int
    let scale: CGFloat
    let hours: Range<Int>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let minute = Calendar.current.component(.hour, from: context.date) * 60 + Calendar.current.component(.minute, from: context.date)
            if hours.contains(minute / 60) {
                HStack(spacing: 4) {
                    Text(context.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(.bone)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(.clay, in: .capsule)
                        .frame(width: 50, alignment: .trailing)
                    Rectangle().fill(.clay).frame(height: 1.5)
                }
                .offset(y: CGFloat(minute - origin) * scale - 9)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

/// What makes the planner read again: another day, or a change in Yaad.
private struct Reload: Hashable {
    let day: Date
    let change: Int
}
