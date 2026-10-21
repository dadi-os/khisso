#if os(macOS)
import SwiftUI

/// Memory: Yaad's whole network of people, memories, plans and places, each
/// joined to what it is about. Kinds switch on and off, a search lights up
/// what matches, and selecting a node opens it in the inspector, where its
/// connections lead on to their nodes.
struct MemoryPage: View {
    let yaad: YaadClient

    @State private var graph: MemoryGraph?
    @State private var selection: String?
    @State private var query = ""
    @State private var kinds = Set(MemoryNode.Kind.allCases)
    @State private var problem: String?
    @State private var loading = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let graph {
                ForceGraph(nodes: nodes(graph), links: links(graph), selection: $selection, highlighted: matches(graph))
                    .transition(.opacity)
                legend(graph)
                    .padding(18)
            } else if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.danger)
                    .padding(18)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(Motion.settle, value: graph == nil)
        .searchable(text: $query, placement: .toolbar, prompt: "Search memory")
        .inspector(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selection = nil } })) {
            if let selected, let graph {
                MemoryCard(node: selected, graph: graph, select: { selection = $0 })
                    .inspectorColumnWidth(min: 280, ideal: 340, max: 460)
            }
        }
        .toolbar {
            Button {
                Task { await load() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: loading)
            }
            .help("Reload the network")
        }
        .navigationTitle("Memory")
        .task { await load() }
    }

    private var selected: MemoryNode? { graph?.nodes.first { $0.id == selection } }

    private func visible(_ graph: MemoryGraph) -> [MemoryNode] { graph.nodes.filter { kinds.contains($0.kind) } }

    private func nodes(_ graph: MemoryGraph) -> [ForceGraph.Node] {
        let shown = visible(graph)
        var degree: [String: Int] = [:]
        for edge in graph.edges {
            degree[edge.srcId, default: 0] += 1
            degree[edge.dstId, default: 0] += 1
        }
        let named = Set(shown.sorted { (degree[$0.id] ?? 0) > (degree[$1.id] ?? 0) }.prefix(14).map(\.id))
        return shown.map { node in
            let weight = 3.5 + 1.6 * log2(1 + Double(node.accessCount)) + 0.4 * Double(min(degree[node.id] ?? 0, 12))
            return ForceGraph.Node(id: node.id, label: node.title, color: MemoryStyle.color(node.kind), radius: min(15, weight), labeled: named.contains(node.id))
        }
    }

    private func links(_ graph: MemoryGraph) -> [ForceGraph.Link] {
        let ids = Set(visible(graph).map(\.id))
        return graph.edges.filter { ids.contains($0.srcId) && ids.contains($0.dstId) }.map { ForceGraph.Link(from: $0.srcId, to: $0.dstId) }
    }

    /// The nodes whose title or body holds the search, or nil while there is none.
    private func matches(_ graph: MemoryGraph) -> Set<String>? {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return nil }
        return Set(graph.nodes.filter { $0.title.localizedCaseInsensitiveContains(needle) || ($0.body?.localizedCaseInsensitiveContains(needle) ?? false) }.map(\.id))
    }

    /// The kinds as chips that switch each on and off, with how many there are.
    private func legend(_ graph: MemoryGraph) -> some View {
        HStack(spacing: 8) {
            ForEach(MemoryNode.Kind.allCases, id: \.self) { kind in
                let on = kinds.contains(kind)
                Button {
                    withAnimation(Motion.snap) {
                        if on { kinds.remove(kind) } else { kinds.insert(kind) }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Circle().fill(MemoryStyle.color(kind)).frame(width: 8, height: 8).opacity(on ? 1 : 0.3)
                        Text(MemoryStyle.plural(kind)).font(.caption.weight(.semibold))
                        Text("\(graph.nodes.filter { $0.kind == kind }.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.inkMuted)
                    }
                    .foregroundStyle(on ? Color.ink : .inkFaint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            graph = try await yaad.graph()
            problem = nil
        } catch is CancellationError {
            return
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// One node in the inspector: its kind, title, date and words, and every
/// connection, each leading to the node at its other end.
private struct MemoryCard: View {
    let node: MemoryNode
    let graph: MemoryGraph
    let select: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 7) {
                    Image(systemName: MemoryStyle.symbol(node.kind))
                    Text(MemoryStyle.singular(node.kind))
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(MemoryStyle.color(node.kind))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(MemoryStyle.color(node.kind).opacity(0.14), in: .capsule)
                Text(node.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.ink)
                    .textSelection(.enabled)
                if let occurredAt = node.occurredAt {
                    Label(occurredAt.formatted(.dateTime.weekday(.wide).month().day().year()), systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                }
                if let body = node.body, !body.isEmpty {
                    MarkdownText(source: body)
                        .textSelection(.enabled)
                }
                let connections = connections
                if !connections.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CONNECTIONS")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.4)
                            .foregroundStyle(.inkFaint)
                        ForEach(connections, id: \.edge.id) { connection in
                            Button { select(connection.other.id) } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(MemoryStyle.color(connection.other.kind)).frame(width: 9, height: 9)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(connection.other.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.ink)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Text(connection.relation).font(.caption).foregroundStyle(.inkMuted)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(10)
                                .background(.boneRaised.opacity(0.7), in: .rect(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("\(node.accessCount == 1 ? "Recalled once" : "Recalled \(node.accessCount) times") · added \(node.createdAt.formatted(.dateTime.month().day().year()))")
                    .font(.caption)
                    .foregroundStyle(.inkFaint)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(node.id)
    }

    /// Each edge touching the node, with the node at its other end and the
    /// edge's type read in its direction.
    private var connections: [(edge: MemoryEdge, other: MemoryNode, relation: String)] {
        let byId = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        return graph.edges.compactMap { edge in
            let words = edge.type.replacingOccurrences(of: "_", with: " ")
            if edge.srcId == node.id, let other = byId[edge.dstId] { return (edge, other, "\(words) →") }
            if edge.dstId == node.id, let other = byId[edge.srcId] { return (edge, other, "← \(words)") }
            return nil
        }
    }
}

/// How each kind of memory reads: its color, symbol and names.
enum MemoryStyle {
    static func color(_ kind: MemoryNode.Kind) -> Color {
        switch kind {
        case .person: .clay
        case .memory: .sageDeep
        case .plan: .tide
        case .place: .daylight
        }
    }

    static func symbol(_ kind: MemoryNode.Kind) -> String {
        switch kind {
        case .person: "person.fill"
        case .memory: "bookmark.fill"
        case .plan: "calendar"
        case .place: "mappin"
        }
    }

    static func singular(_ kind: MemoryNode.Kind) -> String {
        switch kind {
        case .person: "Person"
        case .memory: "Memory"
        case .plan: "Plan"
        case .place: "Place"
        }
    }

    static func plural(_ kind: MemoryNode.Kind) -> String {
        switch kind {
        case .person: "People"
        case .memory: "Memories"
        case .plan: "Plans"
        case .place: "Places"
        }
    }
}
#endif
