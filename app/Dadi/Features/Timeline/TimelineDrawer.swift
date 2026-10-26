import SwiftUI

/// The Timeline's drawer: its four views as tiles, what comes due in the
/// next two weeks, how much of this week is completed, and Tell Dadi, which
/// is how anything on the timeline gets added, moved or dropped.
struct TimelineDrawer: View {
    let yaad: YaadClient
    let mode: TimelineMode
    /// Shows a view and closes the drawer.
    let choose: (TimelineMode) -> Void
    let tellDadi: () -> Void

    /// How far ahead Coming due looks.
    private static let dueDays = 14
    /// How many dues the drawer lists.
    private static let shownDues = 4

    @Environment(LiveData.self) private var live
    @State private var dues: [TimelineItem] = []
    @State private var week: (completed: Int, held: Int)?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(TimelineMode.allCases, id: \.self) { tile($0) }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
            }
            if !dues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    heading("COMING DUE")
                    ForEach(dues) { item in
                        Button { choose(.month) } label: { dueRow(item) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if let week, week.held > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    heading("THIS WEEK")
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Completed").font(.subheadline).foregroundStyle(.ink)
                            Spacer()
                            Text("\(week.completed) of \(week.held)")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(.ink)
                                .contentTransition(.numericText())
                        }
                        ProgressView(value: Double(week.completed), total: Double(week.held))
                            .tint(.sage)
                    }
                    .padding(12)
                    .background(.bone.opacity(0.55), in: .rect(cornerRadius: 16, style: .continuous))
                }
            }
            Button(action: tellDadi) {
                HStack(spacing: 12) {
                    Text("દ")
                        .font(.wordmark(19))
                        .inkCentered(.letter, size: 19)
                        .foregroundStyle(.sageDeep)
                        .frame(width: 32, height: 32)
                        .background(.sage.opacity(0.24), in: .circle)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tell Dadi").font(.body.weight(.semibold)).foregroundStyle(.ink)
                        Text("Add, move or drop anything").font(.footnote).foregroundStyle(.inkMuted)
                    }
                    Spacer()
                }
                .padding(10)
                .background(.sage.opacity(0.16), in: .rect(cornerRadius: 16, style: .continuous))
                .contentShape(.rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .animation(Motion.settle, value: dues)
        .task(id: live.yaad) { await load() }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(1.4)
            .foregroundStyle(.inkFaint)
            .padding(.horizontal, 6)
            .padding(.bottom, 2)
    }

    /// A view's tile, filled sage while it is the one shown.
    private func tile(_ target: TimelineMode) -> some View {
        let current = target == mode
        return Button { choose(target) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: target.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(current ? Color.bone : .sageDeep)
                Text(target.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(current ? Color.bone : .ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(current ? AnyShapeStyle(Color.sageDeep) : AnyShapeStyle(Color.bone.opacity(0.55)), in: .rect(cornerRadius: 16, style: .continuous))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .animation(Motion.snap, value: current)
    }

    private func dueRow(_ item: TimelineItem) -> some View {
        HStack(spacing: 10) {
            Circle().fill(item.completed ? Color.sage : .clay).frame(width: 7, height: 7)
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.ink)
                .strikethrough(item.completed, color: .inkFaint)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let due = item.dueAt {
                Text(Self.when(due))
                    .font(.caption)
                    .foregroundStyle(.inkMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bone.opacity(0.4), in: .rect(cornerRadius: 14, style: .continuous))
        .contentShape(.rect(cornerRadius: 14))
    }

    /// A due in a word or two: "Tonight", "Tomorrow", "Fri", "Nov 3".
    private static func when(_ due: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(due) { return calendar.component(.hour, from: due) >= 17 ? "Tonight" : "Today" }
        if calendar.isDateInTomorrow(due) { return "Tomorrow" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: due)).day!
        return days < 7 ? due.formatted(.dateTime.weekday(.abbreviated)) : due.formatted(.dateTime.month(.abbreviated).day())
    }

    private func load() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        guard let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: today),
              let until = calendar.date(byAdding: .day, value: Self.dueDays, to: today) else { return }
        do {
            async let upcoming = yaad.timeline(.due, from: today, to: until)
            async let sessions = yaad.timeline(.planner, from: monday, to: .now)
            let (d, p) = try await (upcoming, sessions)
            dues = Array(d.filter { !$0.completed }.prefix(Self.shownDues))
            let held = p.filter { !$0.cancelled && ($0.endAt ?? .distantFuture) <= .now }
            week = (held.filter(\.completed).count, held.count)
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
