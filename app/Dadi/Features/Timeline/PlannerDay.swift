import SwiftUI

/// One day of the timeline: what's happening now and next, what is due that
/// day, then the day's timed sessions (Yaad's planner view) on an hour axis,
/// each as tall as its time, with open time left as space and labeled with
/// its length. Commitments are solid, the gym warm, routines quiet, and a
/// cancelled session is struck through. A session's gestures are
/// `SessionGestures`; a drag across the empty day moves a day. The day is
/// read again whenever Yaad announces a change.
struct PlannerDay: View {
    let yaad: YaadClient
    let actions: SessionActions

    @Environment(LiveData.self) private var live
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var blocks: [TimelineItem] = []
    @State private var due: [TimelineItem] = []
    @State private var error: String?
    @State private var direction: Edge = .trailing

    /// Points per minute on the axis.
    private let scale: CGFloat = 1.3

    var body: some View {
        let segments = PlannerLayout.segments(actions.shown(blocks), on: day)
        axis(segments)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
                    move(by: drag.translation.width < 0 ? 1 : -1)
                }
        )
        .task(id: Reload(day: day, change: live.yaad)) { await load() }
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
        direction = days > 0 ? .trailing : .leading
        withAnimation(Motion.settle) {
            blocks = []
            due = []
            day = next
        }
    }

    private func axis(_ segments: [PlannerLayout.Segment]) -> some View {
        let hours = PlannerLayout.hours(segments)
        let origin = hours.lowerBound * 60
        let height = CGFloat(hours.count * 60) * scale
        let now = Calendar.current.component(.hour, from: .now) * 60 + Calendar.current.component(.minute, from: .now)
        let start = Calendar.current.isDateInToday(day) ? UnitPoint(x: 0, y: max(0, min(1, CGFloat(now - 60 - origin) / CGFloat(max(1, hours.count * 60))))) : .top
        return ScrollView {
            VStack(spacing: 14) {
                header
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
                        ForEach(segments) { segment in
                            let width = lane / CGFloat(segment.lanes)
                            BlockView(segment: segment, height: max(30, CGFloat(segment.endMin - segment.startMin) * scale - 3))
                                .sessionGestures(segment.block, actions: actions)
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
        .defaultScrollAnchor(start)
    }

    private func hourLabel(_ hour: Int) -> String {
        Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: day)?.formatted(.dateTime.hour()) ?? "\(hour)"
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
/// is settled, struck through when cancelled or completed, with a check once
/// completed and a pin that opens directions when its place has an address.
private struct BlockView: View {
    let segment: PlannerLayout.Segment
    let height: CGFloat

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
            if block.completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tone.ink)
                    .transition(.scale.combined(with: .opacity))
            } else if let url = Directions.url(to: block.place) {
                Button { openURL(url) } label: {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tone.ink)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Directions to \(block.place?.title ?? block.title)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, height > 40 ? 8 : 5)
        .frame(height: height, alignment: .top)
        .background(tone.fill, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tone.edge, lineWidth: 1))
        .opacity(settled ? 0.55 : 1)
        .scaleEffect(block.completed ? 0.985 : 1)
        .animation(Motion.settle, value: block.completed)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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

/// A clay line across the axis at the current minute.
private struct NowLine: View {
    let origin: Int
    let scale: CGFloat
    let hours: Range<Int>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let minute = Calendar.current.component(.hour, from: context.date) * 60 + Calendar.current.component(.minute, from: context.date)
            if hours.contains(minute / 60) {
                HStack(spacing: 0) {
                    Circle().fill(.clay).frame(width: 9, height: 9)
                    Rectangle().fill(.clay).frame(height: 1.5)
                }
                .padding(.leading, 52)
                .offset(y: CGFloat(minute - origin) * scale - 4.5)
                .allowsHitTesting(false)
            }
        }
    }
}

/// What makes the planner read again: another day, or a change in Yaad.
private struct Reload: Hashable {
    let day: Date
    let change: Int
}
