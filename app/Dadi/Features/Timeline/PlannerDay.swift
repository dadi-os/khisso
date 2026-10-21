import SwiftUI

/// One day of the plan, the only view that shows a day: what's happening now
/// and next, then the day's blocks on an hour axis, each as tall as its time,
/// with open time left as space and labeled with its length. Fixed
/// commitments are solid, the gym warm, the rest quiet. Tap a block for its
/// note and to mark it done. Yaad has no push, so the plan is fetched every
/// two seconds while it is on screen.
struct PlannerDay: View {
    let yaad: YaadClient

    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var blocks: [PlannerBlock] = []
    @State private var error: String?
    @State private var opened: PlannerBlock?
    @State private var direction: Edge = .trailing

    /// Points per minute on the axis.
    private let scale: CGFloat = 1.3
    private let refresh: Duration = .seconds(2)

    var body: some View {
        let segments = PlannerLayout.segments(blocks, on: day)
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
            axis(segments)
                .id(day)
                .transition(.push(from: direction))
        }
        .padding(.horizontal, 20)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
                    move(by: drag.translation.width < 0 ? 1 : -1)
                }
        )
        .sheet(item: $opened) { block in
            BlockCard(block: block, yaad: yaad) { updated in
                if let index = blocks.firstIndex(where: { $0.id == updated.id }) { blocks[index] = updated }
            }
            .presentationDetents([.fraction(0.4), .medium])
            .presentationBackground(.thinMaterial)
        }
        .task(id: day) {
            while !Task.isCancelled {
                await load()
                do { try await Task.sleep(for: refresh) } catch { return }
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
                                .onTapGesture { opened = segment.block }
                        }
                        if Calendar.current.isDateInToday(day) {
                            NowLine(origin: origin, scale: scale, hours: hours)
                        }
                    }
                }
                .frame(height: height + 12)
                .padding(.top, 8)
                .padding(.bottom, 60)
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: block.doneAt != nil ? "checkmark.circle.fill" : PlannerLayout.symbol(block.icon))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tone.ink)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.ink)
                    .strikethrough(block.doneAt != nil, color: .inkFaint)
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

/// A block's card: its time, kind and note, and Mark done.
private struct BlockCard: View {
    let block: PlannerBlock
    let yaad: YaadClient
    let updated: (PlannerBlock) -> Void

    @State private var current: PlannerBlock?
    @State private var working = false
    @State private var problem: String?
    @State private var marked = 0

    var body: some View {
        let shown = current ?? block
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: PlannerLayout.symbol(shown.icon))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Tone(kind: shown.kind).ink)
                    .frame(width: 44, height: 44)
                    .background(Tone(kind: shown.kind).fill, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shown.title).font(.title3.weight(.semibold)).foregroundStyle(.ink)
                    Text("\(shown.startAt.formatted(date: .omitted, time: .shortened)) – \(shown.endAt.formatted(date: .omitted, time: .shortened)) · \(PlannerLayout.span(Int(shown.endAt.timeIntervalSince(shown.startAt) / 60)))")
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                }
            }
            if let note = shown.note {
                Text(note).font(.callout).foregroundStyle(.ink)
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.danger)
            }
            Button {
                toggle(shown)
            } label: {
                Label(shown.doneAt == nil ? "Mark done" : "Mark not done", systemImage: shown.doneAt == nil ? "checkmark.circle" : "arrow.uturn.backward")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(working)
        }
        .padding(24)
        .sensoryFeedback(.success, trigger: marked)
    }

    private func toggle(_ shown: PlannerBlock) {
        working = true
        Task {
            defer { working = false }
            do {
                let next = try await yaad.setDone(shown.doneAt == nil, block: shown.id)
                current = next
                updated(next)
                marked += 1
                problem = nil
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
