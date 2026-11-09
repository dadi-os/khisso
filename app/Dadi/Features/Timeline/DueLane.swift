import SwiftUI

/// Which due items share one pill in the day's due lane, matching thaali's `dueClusters.ts`.
enum DueClusters {
    /// The height of one due tag.
    static let tagHeight: CGFloat = 24
    /// The distance under which two due items share a pill: one tag height plus a 4 pt gap.
    static let gap: CGFloat = tagHeight + 4

    /// Items drawn as one tag (one member) or one `<N> due` pill (several).
    struct Cluster<Item> {
        /// Where the earliest member sits on the axis, where the tag or pill is drawn.
        let y: CGFloat
        /// The members, earliest first; equal positions keep their input order.
        let items: [Item]
    }

    /// Groups items whose positions would collide. Items are taken earliest first, and one joins the
    /// open cluster while it lies less than `gap` below that cluster's first member; otherwise it
    /// opens the next cluster. Items at the same position always share a cluster.
    static func group<Item>(_ positions: [(item: Item, y: CGFloat)], gap: CGFloat = DueClusters.gap) -> [Cluster<Item>] {
        let ordered = positions.enumerated().sorted { ($0.element.y, $0.offset) < ($1.element.y, $1.offset) }.map(\.element)
        var clusters: [Cluster<Item>] = []
        for (item, y) in ordered {
            if let open = clusters.last, y - open.y < gap {
                clusters[clusters.count - 1] = Cluster(y: open.y, items: open.items + [item])
            } else {
                clusters.append(Cluster(y: y, items: [item]))
            }
        }
        return clusters
    }
}

/// The day's due lane, as thaali draws it: each due-at item sits at its time as a clay tag with its
/// title and time, and items too close to draw apart become one `<N> due` pill that opens in place
/// into a list, each row opening the item's details. Only the tags take touches.
struct DueLane: View {
    /// The width of the lane at the right of the day column.
    static let width: CGFloat = 156
    /// The width of an opened cluster's list.
    private static let listWidth: CGFloat = 248
    /// The tallest an opened cluster's list grows before it scrolls.
    private static let listMaxHeight: CGFloat = 280

    /// The day's due items, each with a due time.
    let items: [TimelineItem]
    /// Where a due time falls on the axis, in points from its top.
    let position: (TimelineItem) -> CGFloat
    let height: CGFloat
    /// The id of the first member of the cluster whose list is open.
    @Binding var expanded: String?
    /// Opens an item's details.
    let open: (TimelineItem) -> Void

    var body: some View {
        let clusters = DueClusters.group(items.map { (item: $0, y: position($0)) })
        ZStack(alignment: .topLeading) {
            ForEach(clusters, id: \.items[0].id) { cluster in
                let first = cluster.items[0]
                let isOpen = expanded == first.id
                Group {
                    if cluster.items.count == 1 {
                        Button { open(first) } label: { DueTag(item: first) }
                    } else {
                        Button { withAnimation(Motion.snap) { expanded = isOpen ? nil : first.id } } label: {
                            DueTag(label: "\(cluster.items.count) due", time: first.dueAt)
                        }
                        .accessibilityLabel("\(cluster.items.count) due")
                        .accessibilityAddTraits(isOpen ? .isSelected : [])
                    }
                }
                .buttonStyle(.plain)
                .frame(width: Self.width, height: DueClusters.tagHeight)
                .overlay(alignment: .topTrailing) {
                    if isOpen { list(cluster.items) }
                }
                .offset(y: cluster.y - DueClusters.tagHeight / 2)
                .zIndex(isOpen ? 1 : 0)
            }
        }
        .frame(width: Self.width, height: height, alignment: .topLeading)
    }

    /// An opened cluster's members as tags in time order on a raised card; a row closes the list and opens its item.
    private func list(_ members: [TimelineItem]) -> some View {
        let natural = CGFloat(members.count) * DueClusters.tagHeight + CGFloat(members.count - 1) * 4 + 12
        return ScrollView {
            VStack(spacing: 4) {
                ForEach(members) { member in
                    Button {
                        withAnimation(Motion.snap) { expanded = nil }
                        open(member)
                    } label: { DueTag(item: member) }
                        .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .scrollIndicators(.hidden)
        .frame(width: Self.listWidth, height: min(Self.listMaxHeight, natural))
        .background(Color.boneRaised, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.rule, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 6)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
    }
}

/// One due tag: a 24 pt clay-toned strip with a bold label that truncates and the time at its right edge.
private struct DueTag: View {
    let label: String
    let time: Date?
    let completed: Bool

    /// A tag for one due item: its title and due time.
    init(item: TimelineItem) {
        label = item.title
        time = item.dueAt
        completed = item.completed
    }

    /// A tag for a cluster: `label` in place of a title, `time` of its first member.
    init(label: String, time: Date?) {
        self.label = label
        self.time = time
        completed = false
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .strikethrough(completed, color: .dueInk)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let time {
                Text(time, format: .dateTime.hour().minute())
                    .font(.system(size: 12).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(Color.dueInk)
        .padding(.leading, 11)
        .padding(.trailing, 8)
        .frame(height: DueClusters.tagHeight)
        .background(Color.dueFill)
        .overlay(alignment: .leading) { Rectangle().fill(Color.clay).frame(width: 3) }
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.dueLine, lineWidth: 1))
        .opacity(completed ? 0.6 : 1)
        .contentShape(.rect(cornerRadius: 8))
    }
}
