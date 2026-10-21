import SwiftUI

/// A force graph on a Canvas: nodes bloom out from the center and settle,
/// links are hairlines, and glowing nodes breathe. An interactive graph pans,
/// zooms, labels the node under the pointer and selects the one clicked.
struct ForceGraph: View {
    struct Node: Identifiable, Hashable {
        let id: String
        let label: String
        let color: Color
        let radius: CGFloat
        var glowing = false
        var faint = false
        /// Labeled even when not hovered or selected.
        var labeled = false
    }

    struct Link: Hashable {
        let from: String
        let to: String
    }

    let nodes: [Node]
    let links: [Link]
    @Binding var selection: String?
    var interactive = true
    /// The nodes that stay bright while the rest dim, as for a search; nil dims none.
    var highlighted: Set<String>?

    @State private var layout = ForceLayout(count: 0, links: [])
    @State private var order: [String] = []
    @State private var hovered: String?
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The biggest a settled graph is drawn before any zoom.
    private let maximumFit: CGFloat = 1.5

    var body: some View {
        GeometryReader { proxy in
            let place = placement(in: proxy.size)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !nodes.contains(where: \.glowing))) { context in
                let breath = sin(context.date.timeIntervalSinceReferenceDate * 2.4)
                Canvas { canvas, _ in
                    draw(in: &canvas, place: place, breath: breath)
                }
            }
            .contentShape(.rect)
            .onContinuousHover { phase in
                guard interactive else { return }
                switch phase {
                case .active(let point): hovered = nearest(to: point, place: place)
                case .ended: hovered = nil
                }
            }
            .gesture(interactive ? gestures(place: place) : nil)
            .overlay(alignment: .bottomTrailing) {
                if interactive && (zoom != 1 || pan != .zero) {
                    Button {
                        withAnimation(Motion.snap) {
                            zoom = 1
                            pan = .zero
                        }
                    } label: {
                        Label("Fit", systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .padding(14)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
        .task(id: signature) { await run() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nodes.count) nodes, \(links.count) links")
    }

    /// Changes whenever a node or link comes or goes, which lays the graph out again.
    private var signature: Int {
        var hasher = Hasher()
        for node in nodes { hasher.combine(node.id) }
        for link in links { hasher.combine(link) }
        return hasher.finalize()
    }

    /// Lays the nodes out again, keeping where known ones were, and steps the
    /// layout a tick a frame, off the main thread, until it settles.
    private func run() async {
        let ids = nodes.map(\.id)
        let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let old = Dictionary(uniqueKeysWithValues: zip(order, layout.positions))
        var seed: [Int: CGPoint] = [:]
        for (id, position) in old { if let at = index[id] { seed[at] = position } }
        let edges = links.compactMap { link in index[link.from].flatMap { a in index[link.to].map { ForceLayout.Link(a: a, b: $0) } } }
        let kept = Double(seed.count) / Double(max(ids.count, 1))
        var next = ForceLayout(count: ids.count, links: edges, seed: seed, alpha: kept > 0.8 ? 0.25 : 1)
        order = ids
        if reduceMotion {
            layout = await Task.detached {
                while !next.settled { next.step() }
                return next
            }.value
            return
        }
        layout = next
        while !layout.settled && !Task.isCancelled {
            let current = layout
            layout = await Task.detached {
                var stepped = current
                stepped.step()
                return stepped
            }.value
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
        }
    }

    /// Maps layout points to the view: the graph fitted and centered, then the
    /// reader's zoom and pan.
    private struct Placement {
        let center: CGPoint
        let scale: CGFloat
        let origin: CGPoint

        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - center.x) * scale + origin.x, y: (p.y - center.y) * scale + origin.y)
        }
    }

    private func placement(in size: CGSize) -> Placement {
        let bounds = layout.bounds.insetBy(dx: -40, dy: -40)
        let fit = min(maximumFit, size.width / max(bounds.width, 1), size.height / max(bounds.height, 1))
        let offset = CGSize(width: pan.width + drag.width, height: pan.height + drag.height)
        return Placement(
            center: CGPoint(x: bounds.midX, y: bounds.midY),
            scale: fit * zoom * pinch,
            origin: CGPoint(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
        )
    }

    /// Node radius grows a little with zoom, never past readable.
    private func radius(_ node: Node, _ place: Placement) -> CGFloat {
        node.radius * min(1.6, max(0.55, place.scale.squareRoot()))
    }

    private func draw(in canvas: inout GraphicsContext, place: Placement, breath: Double) {
        guard order.count == nodes.count, layout.positions.count == nodes.count else { return }
        let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let focus = selection ?? hovered
        var quiet = Path()
        var lit = Path()
        for link in links {
            guard let a = index[link.from], let b = index[link.to] else { continue }
            let from = place.point(layout.positions[a])
            let to = place.point(layout.positions[b])
            if link.from == focus || link.to == focus {
                lit.move(to: from)
                lit.addLine(to: to)
            } else {
                quiet.move(to: from)
                quiet.addLine(to: to)
            }
        }
        canvas.stroke(quiet, with: .color(.sageLine.opacity(highlighted == nil ? 0.55 : 0.2)), lineWidth: 0.8)
        canvas.stroke(lit, with: .color(.sageDeep.opacity(0.9)), lineWidth: 1.6)

        for (at, node) in nodes.enumerated() {
            let center = place.point(layout.positions[at])
            let r = radius(node, place)
            let dimmed = highlighted.map { !$0.contains(node.id) } ?? false
            let opacity = dimmed ? 0.14 : node.faint ? 0.4 : 1
            if node.glowing && !dimmed {
                let halo = r * (2 + 0.45 * breath)
                canvas.fill(Circle().path(in: CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2)), with: .color(node.color.opacity(0.16)))
            }
            let disc = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            canvas.fill(Circle().path(in: disc), with: .color(node.color.opacity(opacity)))
            if node.id == selection {
                canvas.stroke(Circle().path(in: disc.insetBy(dx: -4, dy: -4)), with: .color(node.color), lineWidth: 2)
            }
        }

        for (at, node) in nodes.enumerated() where node.labeled || node.id == focus {
            if let highlighted, !highlighted.contains(node.id), node.id != focus { continue }
            let center = place.point(layout.positions[at])
            let label = Text(node.label)
                .font(.caption.weight(node.id == focus ? .bold : .semibold))
                .foregroundStyle(node.id == focus ? Color.ink : .inkMuted)
            canvas.draw(label, at: CGPoint(x: center.x, y: center.y + radius(node, place) + 10))
        }
    }

    private func nearest(to point: CGPoint, place: Placement) -> String? {
        guard layout.positions.count == nodes.count else { return nil }
        var best: (id: String, distance: CGFloat)?
        for (at, node) in nodes.enumerated() {
            let center = place.point(layout.positions[at])
            let distance = hypot(center.x - point.x, center.y - point.y)
            if distance <= radius(node, place) + 8, distance < (best?.distance ?? .infinity) {
                best = (node.id, distance)
            }
        }
        return best?.id
    }

    private func gestures(place: Placement) -> some Gesture {
        let tap = SpatialTapGesture().onEnded { value in
            withAnimation(Motion.snap) { selection = nearest(to: value.location, place: place) }
        }
        let move = DragGesture(minimumDistance: 3)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                pan.width += value.translation.width
                pan.height += value.translation.height
            }
        let magnify = MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in zoom = min(8, max(0.25, zoom * value.magnification)) }
        return tap.simultaneously(with: move).simultaneously(with: magnify)
    }
}
