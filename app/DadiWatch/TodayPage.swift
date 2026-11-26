import SwiftUI

/// Today from the last snapshot: the plan on now and until when, what is next, the rest of the day's plans (declined
/// ones muted), then the checklist, where a tap ticks a task or takes the tick back.
struct TodayPage: View {
    let store: WatchStore

    var body: some View {
        let snapshot = store.snapshot
        TimelineView(.everyMinute) { context in
            let now = context.date
            let blocks = snapshot?.today ?? []
            let current = blocks.first { !$0.declined && $0.startAt <= now && now < $0.endAt }
            let next = blocks.first { !$0.declined && $0.startAt > now }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today")
                        .font(.headline)
                        .foregroundStyle(.sage)
                    if snapshot == nil {
                        Text("Open dadi on your iPhone to bring today here.").font(.footnote).foregroundStyle(.secondary)
                    } else if blocks.isEmpty {
                        Text("Nothing planned").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let current {
                        NowCard(block: current, now: now)
                    }
                    if let next {
                        NextCard(block: next, now: now)
                    }
                    ForEach(blocks.filter { $0.id != current?.id && $0.id != next?.id }) { block in
                        BlockRow(block: block, settled: block.endAt <= now)
                    }
                    if let tasks = snapshot?.tasks {
                        Checklist(tasks: tasks, store: store, now: now)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The plan on now: its title, until when, and how much of it has gone.
private struct NowCard: View {
    let block: WatchSnapshot.Block
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RIGHT NOW")
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(.sage)
            Text(block.title)
                .font(.body.weight(.semibold))
                .lineLimit(2)
            Text("until \(block.endAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ProgressView(value: now.timeIntervalSince(block.startAt), total: max(block.endAt.timeIntervalSince(block.startAt), 1))
                .tint(.sage)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.sage.opacity(0.18), in: .rect(cornerRadius: 14))
    }
}

/// The next plan and how long until it starts.
private struct NextCard: View {
    let block: WatchSnapshot.Block
    let now: Date

    private func until(_ at: Date, now: Date) -> String {
        let minutes = max(0, Int((at.timeIntervalSince(now) / 60).rounded()))
        if minutes < 60 { return "IN \(minutes)M" }
        return minutes % 60 == 0 ? "IN \(minutes / 60)H" : "IN \(minutes / 60)H \(minutes % 60)M"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("UP NEXT · \(until(block.startAt, now: now))")
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(.secondary)
            Text(block.title).font(.footnote.weight(.semibold)).lineLimit(2)
            Text(block.startAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct BlockRow: View {
    let block: WatchSnapshot.Block
    let settled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(block.declined ? Color.secondary : .sage).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                Text(block.title).font(.footnote.weight(.medium)).lineLimit(1)
                Text(block.declined ? "\(block.startAt.formatted(date: .omitted, time: .shortened)) · Declined" : block.startAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(block.declined || settled ? 0.45 : 1)
    }
}

/// Today's tasks under "n of m checked": a tap ticks one or takes the tick back.
private struct Checklist: View {
    let tasks: [WatchSnapshot.Task]
    let store: WatchStore
    let now: Date

    var body: some View {
        let done = tasks.filter { store.ticks[$0.id] ?? $0.done }.count
        VStack(alignment: .leading, spacing: 6) {
            Text(tasks.isEmpty ? "No tasks today" : done == tasks.count ? "All done" : "\(done) of \(tasks.count) checked")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.sage)
                .padding(.top, 6)
            ForEach(tasks) { task in
                let checked = store.ticks[task.id] ?? task.done
                Button { store.tick(task.id, done: !checked) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .font(.footnote)
                            .foregroundStyle(checked ? Color.sage : task.pastDue ? .orange : .secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(task.title)
                                .font(.footnote.weight(.medium))
                                .strikethrough(checked)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if task.pastDue {
                                Text("Past due").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                    .opacity(checked ? 0.5 : 1)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
