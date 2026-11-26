import SwiftUI
import UIKit

/// The one small moment when the last task is ticked: a check that pops once with a ring that fades outward.
/// Still when the list was already complete on arrival or under Reduce Motion.
private struct Completion: View {
    let settled: Bool

    @State private var popped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let still = settled || reduceMotion
        ZStack {
            if !still {
                Circle()
                    .strokeBorder(Color.sage, lineWidth: 2)
                    .scaleEffect(popped ? 1.9 : 1)
                    .opacity(popped ? 0 : 0.5)
            }
            Circle()
                .fill(Color.sageDeep)
                .overlay { CheckStroke().stroke(Color.bone, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).padding(5) }
                .scaleEffect(still || popped ? 1 : 0.5)
        }
        .frame(width: 22, height: 22)
        .onAppear {
            guard !still else { return }
            withAnimation(.spring(duration: 0.32, bounce: 0.45)) { popped = true }
        }
        .accessibilityHidden(true)
    }
}

/// One task of a list: a ring, its title (two lines at most) and ONE meta line that combines its facts ("Past due by
/// 12 days · IBIO 150"). The ring ticks it or takes the tick back; the rest of the row opens its sheet.
private struct ChecklistRow: View {
    let task: PlanTask
    let done: Bool
    let now: Date
    let tick: () -> Void
    let open: () -> Void

    var body: some View {
        let shown = task.marked(done: done)
        let meta = TaskLogic.meta(shown, now: now)
        let urgent = TaskLogic.isUrgent(shown, now: now)
        HStack(alignment: .top, spacing: 12) {
            Button(action: tick) {
                CheckCircle(done: done).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Take back \(task.title)" : "Check off \(task.title)")
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(done ? Color.inkMuted : .ink)
                        .strikethrough(done, color: .inkFaint)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let meta, !done {
                        Text(meta)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(urgent ? Color.lateInk : .inkMuted)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(done ? "Checked" : "Not checked")
        }
        .padding(.leading, -6)
    }
}

/// What makes the checklist read again: another day, or a change in Yaad.
private struct ChecklistReload: Hashable {
    let day: String
    let change: Int
    let retry: Int
}

/// The Checklist: today's tasks as a page of its own, with "n of m checked" and a progress bar, then Past due, Today, a
/// folded Done and, persistently on the right of its header, "Someday · n", which opens the Someday sheet. A swipe
/// right ticks a task, a swipe left messages the agent that keeps it, a tap opens its sheet, and a ticked row settles
/// into Done. A task with no close is Someday and appears only there.
struct ChecklistView: View {
    let yaad: YaadClient
    let actions: PlannerActions
    /// False while dadi is out of reach: what shows is the last answer.
    let online: Bool

    @Environment(LiveData.self) private var live: LiveData?
    @State private var tasks: [PlanTask] = []
    @State private var somedayCount = 0
    @State private var loaded = false
    @State private var error: String?
    @State private var readAt: Date?
    @State private var retries = 0
    @State private var doneOpen = false
    @State private var settledAtLoad: Bool?

    private var day: Date { Calendar.current.startOfDay(for: .now) }

    /// One line of the list.
    private enum Entry: Identifiable {
        case header(String, Int, late: Bool)
        case task(PlanTask)
        case done([PlanTask])
        case empty

        var id: String {
            switch self {
            case .header(let label, _, _): "h:\(label)"
            case .task(let task): "t:\(task.id)"
            case .done: "done"
            case .empty: "empty"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: ChecklistReload(day: TaskLogic.key(day), change: live?.yaad ?? 0, retry: retries)) { await load() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Checklist")
    }

    private var groups: TaskGroups {
        TaskLogic.groups(actions.ticker.placed(tasks), on: day)
    }

    private var progress: (done: Int, total: Int) {
        TaskLogic.progress(TaskLogic.groups(actions.ticker.shown(tasks), on: day))
    }

    private var header: some View {
        let (done, total) = progress
        let complete = total > 0 && done == total
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Checklist").font(.title3.weight(.semibold)).foregroundStyle(.ink)
                Spacer()
                Button { actions.sheet = .someday } label: {
                    HStack(spacing: 4) {
                        Text("Someday · \(somedayCount)").font(.subheadline.weight(.medium)).monospacedDigit()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.inkMuted)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Someday, \(somedayCount)")
            }
            HStack(spacing: 8) {
                if loaded, total > 0 {
                    if complete {
                        HStack(spacing: 8) {
                            Completion(settled: settledAtLoad ?? false)
                            Text("All done").font(.subheadline.weight(.semibold)).foregroundStyle(.sageDeep)
                        }
                        .transition(.opacity)
                    } else {
                        Text("\(done) of \(total) checked")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.inkMuted)
                            .contentTransition(.numericText())
                    }
                }
                Spacer()
            }
            GeometryReader { proxy in
                Capsule().fill(Color.rule)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(complete ? Color.sageDeep : .sage)
                            .frame(width: total == 0 ? 0 : proxy.size.width * CGFloat(done) / CGFloat(total))
                    }
            }
            .frame(height: 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Progress")
            .accessibilityValue("\(done) of \(total) checked")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .animation(Motion.settle, value: done)
    }

    @ViewBuilder private var content: some View {
        if !loaded && error == nil {
            ChecklistSkeleton().padding(.horizontal, 18).padding(.top, 6).frame(maxHeight: .infinity, alignment: .top)
        } else if !loaded, let error {
            ErrorCard(service: "Yaad", status: nil, message: error) { retries += 1 }
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                list(now: context.date)
            }
        }
    }

    private func list(now: Date) -> some View {
        let entries = entries()
        return List {
            FeedBanner(online: online, error: error, readAt: readAt)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 0, leading: 14, bottom: 0, trailing: 14))
            ForEach(entries) { entry in
                row(entry, now: now)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 0, leading: 18, bottom: 0, trailing: 18))
                    .transition(.opacity)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .opacity(online ? 1 : 0.6)
        .animation(PlannerMotion.exit, value: entries.map(\.id))
        .refreshable { retries += 1 }
    }

    private func entries() -> [Entry] {
        let groups = groups
        let (_, total) = progress
        var out: [Entry] = []
        if total == 0 { out.append(.empty) }
        if !groups.pastDue.isEmpty {
            out.append(.header("Past due", groups.pastDue.count, late: true))
            out += groups.pastDue.map(Entry.task)
        }
        if !groups.open.isEmpty {
            out.append(.header(Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()), groups.open.count, late: false))
            out += groups.open.map(Entry.task)
        }
        if !groups.done.isEmpty { out.append(.done(groups.done)) }
        return out
    }

    @ViewBuilder
    private func row(_ entry: Entry, now: Date) -> some View {
        switch entry {
        case .empty:
            EmptyState(title: "Nothing to check off", detail: "Tasks appear here as agents add them.").padding(.vertical, 18)
        case .header(let label, let count, let late):
            HStack(spacing: 7) {
                if late { Circle().fill(Color.lateDot).frame(width: 6, height: 6) }
                Text(label.uppercased()).tracking(1.8)
                Text("\(count)").fontWeight(.medium)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(late ? Color.lateInk : .inkMuted)
            .padding(.top, 12)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
        case .task(let task):
            taskRow(task, now: now)
        case .done(let done):
            Expandable(isOpen: $doneOpen, look: .row) {
                Text("Done").font(.system(size: 12.5, weight: .semibold))
            } trailing: {
                Text("\(done.count)")
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(done) { task in
                        ChecklistRow(task: task, done: actions.ticker.isDone(task), now: now) {
                            actions.ticker.tick(id: task.id, title: task.title, done: !actions.ticker.isDone(task))
                        } open: { actions.sheet = .task(task) }
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private func taskRow(_ task: PlanTask, now: Date) -> some View {
        let done = actions.ticker.isDone(task)
        let agent = actions.agent(for: task.owner)
        return ChecklistRow(task: task, done: done, now: now) {
            actions.ticker.tick(id: task.id, title: task.title, done: !done)
        } open: {
            actions.sheet = .task(task)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { actions.ticker.tick(id: task.id, title: task.title, done: !done) } label: {
                Label(done ? "Take back" : "Check off", systemImage: done ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(.sageDeep)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if agent != nil {
                Button { actions.messageOwner(task.owner) } label: { Label("Message agent", systemImage: "bubble.left") }
                    .tint(.tide)
            }
        }
        .contextMenu {
            Button { actions.ticker.tick(id: task.id, title: task.title, done: !done) } label: {
                Label(done ? "Take back" : "Check off", systemImage: done ? "arrow.uturn.backward" : "checkmark.circle")
            }
            if agent != nil {
                Button { actions.messageOwner(task.owner) } label: { Label("Message agent", systemImage: "bubble.left") }
            }
            Button { UIPasteboard.general.string = task.title } label: { Label("Copy title", systemImage: "doc.on.doc") }
        }
    }

    private func load() async {
        let key = TaskLogic.key(day)
        let today = Calendar.current.startOfDay(for: .now)
        do {
            async let dayTasks = yaad.tasks(on: key)
            async let windowless = yaad.somedayTasks()
            async let dated = yaad.plans(from: today, to: Calendar.current.date(byAdding: .day, value: SomedaySheet.lookAheadDays, to: today)!)
            let (fetched, fetchedSomeday, fetchedPlans) = try await (dayTasks, windowless, dated)
            actions.ticker.settle()
            tasks = fetched
            somedayCount = fetchedSomeday.count + PlanFilter.loose(fetchedPlans).count
            error = nil
            readAt = .now
            if settledAtLoad == nil {
                let (done, total) = TaskLogic.progress(TaskLogic.groups(fetched, on: day))
                settledAtLoad = total > 0 && done == total
            }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        loaded = loaded || error == nil
    }
}
