import SwiftUI

/// What opens from an agent's name above its thread, as thaali's agent popover does: its name and one summary
/// line over what is true of it now, what its newest message leaves open, what it is doing for its job (with
/// Stop), its helper tasks, what it has done by wake, its routines and reminders, and what it is. The wakes
/// reload when the event stream reconnects or reports one changing; the routines when it reports them changing.
struct AgentSheet: View {
    let services: Services
    let agentId: String
    let name: String
    /// The agent as Home holds it, with its live state; nil until Home has read the roster.
    let agent: AgentRecord?
    /// What the running wake has done so far.
    let counts: WakeCounts?
    /// Changes each time Home's event stream reconnects; the sheet reloads on it.
    let connections: Int
    /// Wake events Home has seen for this agent; the wakes reload on it.
    let wakeChanges: Int
    /// Routine and reminder changes Home has seen; the lists reload on it.
    let scheduleChanges: Int
    let nameOf: (String) -> String
    /// Reads the roster again, after the agent was stopped.
    let refreshAgents: () async -> Void
    /// Replaces the sheet's content with another agent's.
    let selectAgent: (String) -> Void
    /// Closes the sheet and opens the agent's thread.
    let openThread: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LiveData.self) private var live: LiveData?
    @State private var standing: Standing?
    @State private var standingError: String?
    @State private var routines: Routines?
    @State private var routinesError: String?
    @State private var confirming = false
    @State private var tasks: [NasTask] = []
    @State private var hostError: String?
    @State private var stop = StopState()

    /// What makes the standing read again: a reconnect, or the agent starting or ending a wake.
    private struct StandingKey: Hashable {
        let connections: Int
        let working: Bool
    }

    /// What makes the routines read again.
    private struct RoutinesKey: Hashable {
        let connections: Int
        let scheduleChanges: Int
    }

    private var feed: RoutinesSection.Feed {
        if let routinesError { return .failed("Couldn't load routines: \(routinesError)") }
        return routines.map { .ready($0) } ?? .loading
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let agent {
                            overview(agent, now: context.date)
                        } else {
                            SkeletonRows(count: 2, height: 72)
                        }
                        if !tasks.isEmpty {
                            HelperTasks(hath: services.hath, nas: services.nas, owner: name, tasks: tasks) { await loadHost() }
                        }
                        if let hostError { problem("Couldn't read the agent's tasks: \(hostError)") }
                        RoutinesSection(feed: feed, cancelRoutine: cancelRoutine, cancelReminder: cancelReminder, message: openThread, now: context.date)
                        WakeTimeline(hath: services.hath, agentId: agentId, nameOf: nameOf, selectAgent: selectAgent, refresh: .init(connections: connections, wakeChanges: wakeChanges), routines: routines)
                        if let standingError { problem("Couldn't read what the thread waits on: \(standingError)") }
                        if let agent { CharterRow(agent: agent) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollIndicators(.hidden)
            .background(Color.boneRaised.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: StandingKey(connections: connections, working: agent?.running.working ?? false)) { await loadStanding() }
        .task(id: RoutinesKey(connections: connections, scheduleChanges: scheduleChanges)) { await loadRoutines() }
        .task(id: live?.nas) { await loadHost() }
    }

    /// The name over its situation line, the facts, and the actions row: one primary action (Reply when the thread
    /// waits on Ankur, else Open thread) and a quiet Stop that confirms in place.
    private func overview(_ agent: AgentRecord, now: Date) -> some View {
        let situation = AgentFacts.situation(agent, standing: standing, now: now)
        let parent = agent.parentAgentId.map { (id: $0, name: nameOf($0)) }
        let facts = AgentFacts.facts(AgentFactsInput(agent: agent, parent: parent, routines: routines, standing: standing, counts: counts, tasks: tasks, nameOf: nameOf, now: now))
        let stoppable = agent.running.working || (agent.running.job != nil && agent.running.job?.stopped == nil)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SheetHeader(title: name) {
                    SituationLine(tone: situation.tone, text: situation.text)
                }
                Button(action: openThread) {
                    Text(standing == nil ? "Open thread" : "Reply").font(.subheadline.weight(.semibold)).padding(.horizontal, 6).frame(minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(.sageDeep)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
            VStack(spacing: 0) {
                ForEach(facts) { fact in
                    FactRow(label: fact.label, hint: fact.hint, late: fact.tone == .late, wrap: fact.wrap, long: fact.long) {
                        if let id = fact.agentId {
                            AgentLink(agentId: id, name: fact.value, select: selectAgent)
                        } else {
                            Text(fact.value)
                        }
                    }
                }
            }
            StopButton(name: name, stop: stop, stoppable: stoppable, confirming: $confirming)
            StopConfirm(stop: stop, confirming: $confirming) { Task { await stopAgent() } }
        }
        .sensoryFeedback(.warning, trigger: stop.pending)
    }

    private func problem(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.danger)
    }

    private func loadStanding() async {
        do {
            standing = try await Standing.read(hath: services.hath, agentId: agentId)
            standingError = nil
        } catch is CancellationError {
            return
        } catch {
            standingError = error.localizedDescription
        }
    }

    private func loadRoutines() async {
        do {
            routines = try await services.hath.routines(agentId: agentId)
            routinesError = nil
        } catch is CancellationError {
            return
        } catch {
            routinesError = error.localizedDescription
        }
    }

    private func cancelRoutine(_ id: String) async throws {
        try await services.hath.cancelRoutine(id)
        await loadRoutines()
    }

    private func cancelReminder(_ id: String) async throws {
        try await services.hath.cancelReminder(id)
        await loadRoutines()
    }

    /// Stops the agent's run and job, then reads the roster and its helper tasks again.
    private func stopAgent() async {
        stop = StopState(pending: true)
        do {
            stop = StopState(result: try await services.hath.stop(agentId: agentId))
        } catch {
            stop = StopState(error: error.localizedDescription)
        }
        await refreshAgents()
        await loadHost()
    }

    /// Reads the helper tasks this agent owns, newest activity first.
    private func loadHost() async {
        do {
            tasks = try await services.nas.tasks().filter { $0.owner == agentId }.sorted { $0.lastActivity > $1.lastActivity }
            hostError = nil
        } catch is CancellationError {
            return
        } catch {
            hostError = error.localizedDescription
        }
    }
}
