import SwiftUI

/// One day of the plan, the only view that shows a day: what's happening now
/// and next, then the day's blocks on an hour axis, each as tall as its time,
/// with open time left as space and labeled with its length. Fixed
/// commitments are solid, the gym warm, the rest quiet. Tap a block for its
/// note and to mark it done; marking shows at once and goes back, with the
/// reason, if Yaad does not save it. The plan is read again whenever Yaad
/// announces a change.
struct PlannerDay: View {
    let yaad: YaadClient

    @Environment(LiveData.self) private var live
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var blocks: [PlannerBlock] = []
    @State private var error: String?
    @State private var opened: PlannerBlock?
    @State private var direction: Edge = .trailing
    /// Done or not done as Ankur last marked each block, shown over what Yaad
    /// returns until his save lands.
    @State private var marks: [String: Mark] = [:]
    @State private var failure: MarkFailure?

    /// Points per minute on the axis.
    private let scale: CGFloat = 1.3

    var body: some View {
        let segments = PlannerLayout.segments(shown, on: day)
        axis(segments)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
                    move(by: drag.translation.width < 0 ? 1 : -1)
                }
        )
        .sheet(item: $opened) { block in
            BlockCard(block: shown.first { $0.id == block.id } ?? block, problem: failure?.blockId == block.id ? failure?.message : nil) {
                mark(shown.first { $0.id == block.id } ?? block)
            }
            .fittedSheet()
            .presentationBackground(.thinMaterial)
        }
        .task(id: Reload(day: day, change: live.yaad)) { await load() }
    }

    /// Yaad's blocks with Ankur's unsaved marks over them.
    private var shown: [PlannerBlock] {
        blocks.map { block in marks[block.id].map { block.marked($0) } ?? block }
    }

    /// Marks `block` done if it is open and open if it is done, on screen at
    /// once, then saves it; a failed save puts it back and says why.
    private func mark(_ block: PlannerBlock) {
        let next = Mark(done: block.doneAt == nil, at: .now)
        withAnimation(Motion.pop) {
            marks[block.id] = next
            failure = nil
        }
        Task {
            do {
                let saved = try await yaad.setDone(next.done, block: block.id)
                guard marks[block.id] == next else { return }
                if let index = blocks.firstIndex(where: { $0.id == saved.id }) { blocks[index] = saved }
                marks[block.id] = nil
            } catch is CancellationError {
                guard marks[block.id] == next else { return }
                withAnimation(Motion.settle) { marks[block.id] = nil }
            } catch {
                guard marks[block.id] == next else { return }
                withAnimation(Motion.settle) {
                    marks[block.id] = nil
                    failure = MarkFailure(blockId: block.id, title: block.title, done: next.done, message: error.localizedDescription)
                }
            }
        }
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
            failure = nil
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
                if let failure, opened?.id != failure.blockId {
                    Label("\(failure.title) wasn't marked \(failure.done ? "done" : "not done"): \(failure.message)", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.danger)
                        .transition(.opacity)
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
                                .frame(width: width - 4)
                                .offset(x: 56 + width * CGFloat(segment.lane), y: CGFloat(segment.startMin - origin) * scale + 1.5)
                                .onTapGesture {
                                    if failure?.blockId != segment.id { failure = nil }
                                    opened = segment.block
                                }
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
        .sensoryFeedback(.error, trigger: failure) { $1 != nil }
    }

    private func hourLabel(_ hour: Int) -> String {
        Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: day)?.formatted(.dateTime.hour()) ?? "\(hour)"
    }

    private func load() async {
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return }
        do {
            let fetched = try await yaad.planner(from: day, to: end)
            if fetched != blocks { withAnimation(Motion.settle) { blocks = fetched } }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// How strongly a block stands out: fixed commitments solid, the gym warm,
/// everything else quiet, as in thaali.
private enum Tone {
    case solid, warm, quiet

    init(kind: String) {
        switch kind {
        case "class", "exam", "fixed": self = .solid
        case "gym": self = .warm
        default: self = .quiet
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

/// One block on the axis: its glyph, title and time, toned by kind, faded
/// once it is settled.
private struct BlockView: View {
    let segment: PlannerLayout.Segment
    let height: CGFloat

    var body: some View {
        let block = segment.block
        let tone = Tone(kind: block.kind)
        let settled = PlannerLayout.isSettled(block, now: .now)
        let done = block.doneAt != nil
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : PlannerLayout.symbol(block.icon))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tone.ink)
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.ink)
                    .strikethrough(done, color: .inkFaint)
                    .lineLimit(height > 50 ? 2 : 1)
                if height > 44 {
                    Text("\(block.startAt.formatted(date: .omitted, time: .shortened)) – \(block.endAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.inkMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, height > 40 ? 8 : 5)
        .frame(height: height, alignment: .top)
        .background(tone.fill, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tone.edge, lineWidth: 1))
        .opacity(settled ? 0.55 : 1)
        .scaleEffect(done ? 0.985 : 1)
        .animation(Motion.settle, value: done)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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
                part("NOW", title: current?.block.title ?? "Open time", detail: current.map { "until \($0.block.endAt.formatted(date: .omitted, time: .shortened))" })
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

/// A block's card: its time, kind and note, and Mark done. Marking draws a
/// check into the block's glyph and morphs the button between Mark done and
/// Done, the same way back; `problem` is why the last mark was not saved.
private struct BlockCard: View {
    let block: PlannerBlock
    let problem: String?
    let toggle: () -> Void

    @State private var tap = Tap()

    /// A press of the button and which way it marked, for its haptic.
    private struct Tap: Equatable {
        var count = 0
        var done = false
    }

    var body: some View {
        let done = block.doneAt != nil
        let tone = Tone(kind: block.kind)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                DoneGlyph(symbol: PlannerLayout.symbol(block.icon), tone: tone, done: done)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(done ? .inkMuted : .ink)
                    Text("\(block.startAt.formatted(date: .omitted, time: .shortened)) – \(block.endAt.formatted(date: .omitted, time: .shortened)) · \(PlannerLayout.span(Int(block.endAt.timeIntervalSince(block.startAt) / 60)))")
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                }
                .animation(Motion.settle, value: done)
            }
            if let note = block.note {
                Text(note).font(.callout).foregroundStyle(.ink)
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
            Button {
                tap = Tap(count: tap.count + 1, done: !done)
                toggle()
            } label: {
                Label {
                    Text(done ? "Done" : "Mark done")
                        .contentTransition(.interpolate)
                } icon: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(done ? .sage : .sageDeep)
            .controlSize(.large)
            .accessibilityHint(done ? "Marks it not done" : "")
            .animation(Motion.pop, value: done)
        }
        .padding(24)
        .animation(Motion.snap, value: problem)
        .sensoryFeedback(trigger: tap) { _, new in new.done ? .success : .impact(flexibility: .soft) }
    }
}

/// A block's glyph in its toned circle; once done the circle fills sage and a
/// check draws itself in where the glyph was, with a small pop, and undraws
/// the same way when it is opened again.
private struct DoneGlyph: View {
    let symbol: String
    let tone: Tone
    let done: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(done ? Color.sageDeep : tone.fill)
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tone.ink)
                .opacity(done ? 0 : 1)
                .scaleEffect(done ? 0.4 : 1)
                .blur(radius: done ? 3 : 0)
            CheckStroke()
                .trim(from: 0, to: done ? 1 : 0)
                .stroke(.bone, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: 18, height: 13)
                .animation(done ? .easeOut(duration: 0.32).delay(0.1) : .easeIn(duration: 0.2), value: done)
        }
        .frame(width: 44, height: 44)
        .animation(Motion.snap, value: done)
        .keyframeAnimator(initialValue: 1.0, trigger: done) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(0.86, duration: 0.12)
            SpringKeyframe(1.08, duration: 0.22, spring: .bouncy)
            SpringKeyframe(1, duration: 0.3, spring: .smooth)
        }
        .accessibilityHidden(true)
    }
}

/// A check mark from its short arm to the tip of its long one, so trimming it
/// draws it as a pen would.
private struct CheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
    }
}

/// One mark Ankur made, told apart from a later mark of the same block so an
/// older save landing late does not undo a newer one.
private struct Mark: Equatable {
    let done: Bool
    let at: Date
    let id = UUID()
}

/// A mark Yaad did not save: which block, which way, and why.
private struct MarkFailure: Equatable {
    let blockId: String
    let title: String
    let done: Bool
    let message: String
}

private extension PlannerBlock {
    /// This block as `mark` leaves it: done when it was made, or open.
    func marked(_ mark: Mark) -> PlannerBlock {
        PlannerBlock(id: id, startAt: startAt, endAt: endAt, title: title, note: note, kind: kind, icon: icon, fixed: fixed, doneAt: mark.done ? (doneAt ?? mark.at) : nil)
    }
}

/// What makes the planner read again: another day, or a change in Yaad.
private struct Reload: Hashable {
    let day: Date
    let change: Int
}
