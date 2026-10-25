import SwiftUI

/// Today's planner from the last snapshot: what is on now and until when,
/// what is next, then the rest of the day, completed and past sessions faded.
struct TodayPage: View {
    let snapshot: WatchSnapshot?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let blocks = snapshot?.today.filter { Calendar.current.isDate($0.startAt, inSameDayAs: now) || $0.endAt > now && $0.startAt < now } ?? []
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today")
                        .font(.headline)
                        .foregroundStyle(.sage)
                    if snapshot == nil {
                        Text("Open dadi on your iPhone to bring today here.").font(.footnote).foregroundStyle(.secondary)
                    } else if blocks.isEmpty {
                        Text("Nothing planned today.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let current = blocks.first(where: { $0.startAt <= now && now < $0.endAt }) {
                        NowCard(block: current, now: now)
                    }
                    ForEach(blocks.filter { !($0.startAt <= now && now < $0.endAt) }) { block in
                        BlockRow(block: block, settled: block.done || block.endAt <= now)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The block on now: its title, until when, and how much of it has gone.
private struct NowCard: View {
    let block: WatchSnapshot.Block
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NOW")
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

private struct BlockRow: View {
    let block: WatchSnapshot.Block
    let settled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: block.done ? "checkmark.circle.fill" : "circle")
                .font(.footnote)
                .foregroundStyle(.sage)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(block.title).font(.footnote.weight(.medium)).lineLimit(1)
                Text(block.startAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(settled ? 0.45 : 1)
    }
}
