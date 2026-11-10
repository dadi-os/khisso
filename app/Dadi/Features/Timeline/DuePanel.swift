import SwiftUI

/// What the day's Due panel decides without drawing: its order, its height cap and how urgent an item is.
enum DueList {
    /// The share of the page's height the panel may take before it scrolls inside.
    static let capFraction: CGFloat = 1.0 / 3
    /// How close a due time must be, in seconds, to read as soon.
    static let soonWithin: TimeInterval = 2 * 3600

    /// How pressing an item is at a moment.
    enum Urgency: Equatable {
        case overdue
        case soon
        case later
    }

    /// `items` in time order; items due at the same time keep their input order.
    static func ordered(_ items: [TimelineItem]) -> [TimelineItem] {
        items.enumerated()
            .sorted { ($0.element.dueAt ?? .distantFuture, $0.offset) < ($1.element.dueAt ?? .distantFuture, $1.offset) }
            .map(\.element)
    }

    /// The panel's height: what its rows need, never more than `capFraction` of `available`.
    static func height(content: CGFloat, available: CGFloat) -> CGFloat {
        min(content, available * capFraction)
    }

    /// A completed item is never pressing; otherwise overdue once its time has passed and soon within `soonWithin` of it.
    static func urgency(_ item: TimelineItem, now: Date) -> Urgency {
        guard !item.completed, let due = item.dueAt else { return .later }
        if due <= now { return .overdue }
        return due.timeIntervalSince(now) <= soonWithin ? .soon : .later
    }
}

/// The day's Due panel, pinned under the date selector: every due-at item of the day in time order,
/// in its own scroll that grows to its rows up to a third of the page. The header names it with the
/// count and collapses it; each row opens the item's details.
struct DuePanel: View {
    /// The day's due items, in any order.
    let items: [TimelineItem]
    /// The page's height, which the panel's cap is a share of.
    let available: CGFloat
    @Binding var collapsed: Bool
    /// Opens an item's details.
    let open: (TimelineItem) -> Void

    @State private var content: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(Motion.snap) { collapsed.toggle() } } label: {
                HStack(spacing: 8) {
                    Text("Due").font(.subheadline.weight(.semibold)).foregroundStyle(Color.dueInk)
                    Text("\(items.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.dueInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Color.clay.opacity(0.18), in: .capsule)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.dueInk)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Due, \(items.count)")
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
            if !collapsed {
                if items.isEmpty {
                    Text("Nothing due")
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                } else {
                    ScrollView {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            VStack(spacing: 0) {
                                ForEach(DueList.ordered(items)) { item in
                                    DueRow(item: item, urgency: DueList.urgency(item, now: context.date), open: { open(item) })
                                }
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { content = $0 }
                    }
                    .scrollIndicators(.automatic)
                    .frame(height: DueList.height(content: content, available: available))
                }
            }
        }
        .background(Color.dueFill, in: .rect(cornerRadius: 16, style: .continuous))
        .background(Color.boneRaised, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.dueLine, lineWidth: 1))
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// One due row: its time, its title and owner, and a mark when it is overdue or soon.
private struct DueRow: View {
    let item: TimelineItem
    let urgency: DueList.Urgency
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.dueAt ?? .distantPast, format: .dateTime.hour().minute())
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(urgency == .later ? Color.dueInk : .clay)
                    .lineLimit(1)
                    .fixedSize()
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.subheadline.weight(urgency == .later ? .medium : .bold))
                        .foregroundStyle(.ink)
                        .strikethrough(item.completed, color: .inkFaint)
                        .lineLimit(2)
                    if let owner = item.ownerAgent {
                        Text(owner).font(.caption).foregroundStyle(.inkMuted).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if urgency != .later {
                    Text(urgency == .overdue ? "Overdue" : "Soon")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.bone)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.clay, in: .capsule)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .overlay(alignment: .top) { Rectangle().fill(Color.dueLine).frame(height: 1) }
            .opacity(item.completed ? 0.6 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
