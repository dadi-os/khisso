#if os(macOS)
import SwiftUI

/// Agents: every agent Hath runs as a living graph, each joined to the agent
/// that made it. Working agents breathe and retired ones are faint. Selecting
/// one opens its card in the inspector, with its sessions and its chat.
struct AgentsPage: View {
    let hath: HathClient
    /// Agents with a lane running, from Hath's live events.
    let running: Set<String>
    let open: (String) -> Void

    @State private var agents: [AgentRecord] = []
    @State private var selection: String?
    @State private var problem: String?
    @State private var showRetired = false

    private let refresh: Duration = .seconds(5)

    var body: some View {
        ZStack(alignment: .topLeading) {
            AgentGraph(agents: shown, running: running, selection: $selection, interactive: true)
            VStack(alignment: .leading, spacing: 8) {
                summary
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.danger)
                }
            }
            .padding(18)
        }
        .inspector(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selection = nil } })) {
            if let selected {
                AgentCard(agent: selected, agents: agents, working: isWorking(selected), select: { selection = $0 }, open: open)
                    .inspectorColumnWidth(min: 280, ideal: 330, max: 440)
            }
        }
        .toolbar {
            Toggle(isOn: $showRetired.animation(Motion.settle)) {
                Label("Show retired", systemImage: "archivebox")
            }
            .help("Show retired agents")
        }
        .navigationTitle("Agents")
        .task {
            while !Task.isCancelled {
                await load()
                do { try await Task.sleep(for: refresh) } catch { return }
            }
        }
    }

    private var shown: [AgentRecord] { agents.filter { showRetired || $0.active } }

    private var selected: AgentRecord? { agents.first { $0.id == selection } }

    private func isWorking(_ agent: AgentRecord) -> Bool { agent.isRunning || running.contains(agent.id) }

    private var summary: some View {
        let active = agents.filter(\.active)
        let working = active.filter(isWorking).count
        return HStack(spacing: 10) {
            Text("\(active.count) agents")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.ink)
            if working > 0 {
                HStack(spacing: 6) {
                    Circle().fill(.sage).frame(width: 7, height: 7)
                        .phaseAnimator([1.0, 0.4]) { dot, phase in dot.opacity(phase) } animation: { _ in Motion.breath }
                    Text("\(working) working").font(.subheadline).foregroundStyle(.sageText)
                }
                .transition(.opacity)
            }
        }
        .contentTransition(.numericText())
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .animation(Motion.settle, value: working)
    }

    private func load() async {
        do {
            agents = try await hath.agents()
            problem = nil
        } catch is CancellationError {
            return
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// The agent graph: top-level agents larger, each child linked to its parent,
/// working agents breathing. Home's tile draws it small and still.
struct AgentGraph: View {
    let agents: [AgentRecord]
    let running: Set<String>
    @Binding var selection: String?
    let interactive: Bool

    var body: some View {
        let ids = Set(agents.map(\.id))
        ForceGraph(
            nodes: agents.map { agent in
                ForceGraph.Node(
                    id: agent.id,
                    label: Agent.displayName(agent.name),
                    color: Agent.hue(agent.id),
                    radius: agent.parentAgentId.map(ids.contains) == true ? 8 : 12,
                    glowing: agent.isRunning || running.contains(agent.id),
                    faint: !agent.active,
                    labeled: interactive
                )
            },
            links: agents.compactMap { agent in
                agent.parentAgentId.flatMap { ids.contains($0) ? ForceGraph.Link(from: $0, to: agent.id) : nil }
            },
            selection: $selection,
            interactive: interactive
        )
    }
}

/// One agent in the inspector: who it is, who made it and whom it made, what
/// it holds open, its instructions, and its chat.
private struct AgentCard: View {
    let agent: AgentRecord
    let agents: [AgentRecord]
    let working: Bool
    let select: (String) -> Void
    let open: (String) -> Void

    @State private var showPrompt = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Text(String(agent.name.prefix(1)).uppercased())
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.bone)
                        .frame(width: 52, height: 52)
                        .background(Agent.hue(agent.id), in: .circle)
                        .shadow(color: Agent.hue(agent.id).opacity(working ? 0.5 : 0), radius: 12)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Agent.displayName(agent.name)).font(.title3.weight(.semibold)).foregroundStyle(.ink)
                        Text(status).font(.subheadline).foregroundStyle(working ? Color.sageText : .inkMuted)
                    }
                }
                if agent.active {
                    Button { open(agent.id) } label: {
                        Label("Open chat", systemImage: "bubble.left.and.text.bubble.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.sageDeep)
                    .controlSize(.large)
                }
                if let parent = agents.first(where: { $0.id == agent.parentAgentId }) {
                    section("Made by") { agentButton(parent) }
                }
                let children = agents.filter { $0.parentAgentId == agent.id }
                if !children.isEmpty {
                    section("Made") {
                        VStack(alignment: .leading, spacing: 6) { ForEach(children) { agentButton($0) } }
                    }
                }
                if !agent.sessions.browsers.isEmpty || !agent.sessions.terminals.isEmpty {
                    section("Open now") {
                        VStack(alignment: .leading, spacing: 8) {
                            if !agent.sessions.browsers.isEmpty {
                                Label(agent.sessions.browsers.count == 1 ? "1 browser" : "\(agent.sessions.browsers.count) browsers", systemImage: "safari")
                                    .font(.subheadline)
                            }
                            ForEach(agent.sessions.terminals, id: \.id) { terminal in
                                Label {
                                    Text(terminal.lastCommand ?? "No command yet").font(.caption.monospaced()).lineLimit(2)
                                } icon: {
                                    Image(systemName: "terminal")
                                }
                            }
                        }
                        .foregroundStyle(.ink)
                    }
                }
                section("Instructions") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(agent.systemPrompt)
                            .font(.footnote)
                            .foregroundStyle(.ink)
                            .lineLimit(showPrompt ? nil : 6)
                            .textSelection(.enabled)
                        Button(showPrompt ? "Show less" : "Show all") { withAnimation(Motion.settle) { showPrompt.toggle() } }
                            .buttonStyle(.link)
                            .tint(.sageDeep)
                            .font(.footnote.weight(.semibold))
                    }
                }
                Text("Made \(agent.createdAt.formatted(.dateTime.month().day().year()))")
                    .font(.caption)
                    .foregroundStyle(.inkFaint)
            }
            .padding(20)
        }
        .id(agent.id)
        .transition(.opacity)
    }

    private var status: String {
        if !agent.active { return "Retired" }
        if agent.running.reasoning { return "Thinking" }
        if working { return "Working" }
        return "Idle"
    }

    private func agentButton(_ other: AgentRecord) -> some View {
        Button { select(other.id) } label: {
            HStack(spacing: 8) {
                Circle().fill(Agent.hue(other.id)).frame(width: 9, height: 9)
                Text(Agent.displayName(other.name)).font(.subheadline.weight(.medium)).foregroundStyle(.ink)
                if !other.active { Text("Retired").font(.caption).foregroundStyle(.inkFaint) }
            }
        }
        .buttonStyle(.plain)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.inkFaint)
            content()
        }
    }
}
#endif
