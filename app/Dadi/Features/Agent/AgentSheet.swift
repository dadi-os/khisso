import SwiftUI

/// What opens from an agent's name above its thread, as thaali's agent
/// popover does: its status block (job, work, last calls, tasks, queued
/// messages), its live browser, when it was made and last
/// active, its scheduled messages, system prompt, tools, and its activity by
/// wake. Activity follows the agent's lanes: it reloads when they change and
/// every two seconds while one runs.
struct AgentSheet: View {
    let services: Services
    let agentId: String
    let name: String
    /// The agent's lanes running now.
    let lanes: Set<Lane>
    /// Changes each time Home's event stream reconnects; the sheet reloads on it.
    let connections: Int
    let nameOf: (String) -> String

    /// Wakes the activity feed loads, every row of each.
    private static let activityWakes = 10

    /// How often a busy agent's activity is read again.
    private static let poll: Duration = .seconds(2)

    @Environment(\.dismiss) private var dismiss
    @State private var detail: AgentDetail?
    @State private var detailError: String?
    @State private var schedules: [ScheduledMessage]?
    @State private var scheduleError: String?
    @State private var liveBrowser: Int?
    @State private var terminalCaption: String?
    @State private var hostError: String?
    @State private var wakes: [ActivityWake]?
    @State private var lastLogAt: Date?
    @State private var logsError: String?
    @State private var promptOpen = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let waiting = detail?.agent.running.waitingOn, detail?.agent.running.status == nil {
                        Text(AgentStatusView.waitingLabel(waiting)).font(.footnote).foregroundStyle(.inkMuted)
                    }
                    if let status = detail?.agent.running.status {
                        section("STATUS") { AgentStatusBlock(view: AgentStatusView.make(status, nameOf: nameOf)) }
                    }
                    if let liveBrowser {
                        VStack(alignment: .leading, spacing: 8) {
                            if let terminalCaption {
                                Text(terminalCaption)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.inkMuted)
                                    .lineLimit(1)
                            }
                            BrowserView(nas: services.nas, browserId: liveBrowser)
                        }
                    }
                    if let hostError {
                        problem("Couldn't check the agent's browser: \(hostError)")
                    }
                    facts
                    if let scheduleError {
                        problem("Couldn't load schedules: \(scheduleError)")
                    } else if let schedules, !schedules.isEmpty {
                        section("SCHEDULED") {
                            ScheduleSection(hath: services.hath, agentId: agentId, schedules: schedules, nameOf: nameOf, changed: loadSchedules)
                        }
                    }
                    if let detailError {
                        problem("Couldn't load agent detail: \(detailError)")
                    }
                    if let detail {
                        section("SYSTEM PROMPT") { prompt(detail.agent.systemPrompt) }
                        section("TOOLS") { tools(detail.tools) }
                    }
                    section("ACTIVITY") {
                        if let logsError {
                            problem("Couldn't load activity: \(logsError)")
                        } else if let wakes {
                            ActivityFeed(wakes: wakes, lanes: lanes, nameOf: nameOf)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Color.boneRaised.ignoresSafeArea())
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: connections) {
            async let schedules: Void = loadSchedules()
            await loadDetail()
            async let host: Void = loadHost()
            _ = await (schedules, host)
        }
        .task(id: lanes) { await followActivity() }
    }

    /// The agent's state in a pill: processing plays the flowing dots, working
    /// runs the sheen, and an idle or retired agent sits quiet.
    private var header: some View {
        HStack(spacing: 8) {
            if lanes.contains(.process) {
                ProcessingMark()
            } else {
                Circle()
                    .fill(!lanes.isEmpty ? Color.sageDeep : isActive ? .sage : .inkFaint)
                    .frame(width: 7, height: 7)
            }
            Text(status)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(lanes.isEmpty ? Color.inkMuted : .sageText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(lanes.isEmpty ? Color.ink.opacity(0.05) : .sage.opacity(0.14), in: .capsule)
        .laneSheen(lanes.contains(.work), in: Capsule())
        .animation(Motion.settle, value: lanes)
    }

    private var isActive: Bool { detail?.agent.active ?? true }

    private var status: String {
        if !isActive { return "Retired" }
        if lanes.isEmpty { return "Idle" }
        return [Lane.process, .work].filter(lanes.contains).map(\.label).joined(separator: " + ").capitalized
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            if let agent = detail?.agent {
                GridRow {
                    Text("Created").foregroundStyle(.inkFaint)
                    Text(agent.createdAt, format: .relative(presentation: .named)).foregroundStyle(.inkMuted)
                }
                GridRow {
                    Text("Last active").foregroundStyle(.inkFaint)
                    if !lanes.isEmpty {
                        Text("Now").foregroundStyle(.inkMuted)
                    } else {
                        Text(lastLogAt ?? agent.updatedAt, format: .relative(presentation: .named)).foregroundStyle(.inkMuted)
                    }
                }
                if let parent = agent.parentAgentId {
                    GridRow {
                        Text("Parent").foregroundStyle(.inkFaint)
                        Text(nameOf(parent)).foregroundStyle(.sageDeep)
                    }
                }
            }
        }
        .font(.subheadline)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.inkFaint)
            content()
        }
    }

    private func problem(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.danger)
    }

    private func prompt(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AgentMarkdown(source: text, compact: true)
                .frame(maxHeight: promptOpen ? nil : 130, alignment: .top)
                .clipped()
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: promptOpen ? 1 : 0.55), .init(color: promptOpen ? .black : .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                }
            if text.count > 160 {
                Button(promptOpen ? "Collapse" : "Expand") { withAnimation(Motion.settle) { promptOpen.toggle() } }
                    .font(.footnote)
                    .foregroundStyle(.sageDeep)
            }
        }
    }

    @ViewBuilder
    private func tools(_ tools: [AgentTool]) -> some View {
        if tools.isEmpty {
            Text("No granted tools.").font(.footnote).foregroundStyle(.inkMuted)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(tools, id: \.name) { tool in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.name).font(.footnote.weight(.semibold)).foregroundStyle(.ink)
                        Text(InlineMarkdown.attributed(tool.description)).font(.caption).foregroundStyle(.inkMuted)
                    }
                }
            }
        }
    }

    private func loadDetail() async {
        do {
            detail = try await services.hath.agent(agentId)
            detailError = nil
        } catch is CancellationError {
            return
        } catch {
            detailError = error.localizedDescription
        }
    }

    private func loadSchedules() async {
        do {
            schedules = try await services.hath.schedules(agentId: agentId)
            scheduleError = nil
        } catch is CancellationError {
            return
        } catch {
            scheduleError = error.localizedDescription
        }
    }

    /// Finds the agent's newest task holding a live browser on Nas, and the purpose of its newest live terminal task.
    private func loadHost() async {
        guard let sessions = detail?.agent.sessions else { return }
        do {
            let nasTasks = try await services.nas.tasks()
            let live = sessions.tasks.compactMap { row in nasTasks.first { $0.task == row.id && $0.resource != nil } }
            liveBrowser = live.first { $0.kind == "browser" }?.resource.flatMap(Int.init)
            terminalCaption = live.first { $0.kind == "terminal" }?.purpose
            hostError = nil
        } catch is CancellationError {
            return
        } catch {
            hostError = error.localizedDescription
        }
    }

    /// Reads the activity now and while a lane runs, until the sheet closes or the lanes change.
    private func followActivity() async {
        repeat {
            await loadDetail()
            await loadActivity()
            if lanes.isEmpty { return }
            do { try await Task.sleep(for: Self.poll) } catch { return }
        } while !Task.isCancelled
    }

    private func loadActivity() async {
        do {
            let logs = try await services.hath.logs(agentId: agentId, wakes: Self.activityWakes)
            wakes = Activity.carryKeys(from: wakes ?? [], to: Activity.wakes(from: logs))
            lastLogAt = logs.first?.createdAt
            logsError = nil
        } catch is CancellationError {
            return
        } catch {
            logsError = error.localizedDescription
        }
    }
}
