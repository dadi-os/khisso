import SwiftUI

/// What opens from an agent's name above its thread, as thaali's agent popover does: its name and one
/// summary line over what is true of it now, its state strip, its helper tasks (with Stop), what it is doing
/// and has done by wake, its scheduled messages and what it is. Wakes reload when the event stream
/// reconnects or reports one changing.
struct AgentSheet: View {
    let services: Services
    let agentId: String
    let name: String
    /// The agent's lanes running now.
    let lanes: Set<Lane>
    /// Changes each time Home's event stream reconnects; the sheet reloads on it.
    let connections: Int
    /// Wake events Home has seen for this agent; the wakes reload on it.
    let wakeChanges: Int
    let nameOf: (String) -> String
    /// Replaces the sheet's content with another agent's.
    let selectAgent: (String) -> Void
    /// Closes the sheet and opens the agent's thread.
    let openThread: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var detail: AgentDetail?
    @State private var detailError: String?
    @State private var schedules: [ScheduledMessage]?
    @State private var scheduleError: String?
    @State private var schedulesOpen = false
    @State private var tasks: [NasTask] = []
    @Environment(LiveData.self) private var live: LiveData?
    @State private var hostError: String?

    /// What makes the agent read again: its lanes, a reconnect, a wake event.
    private struct Reload: Hashable {
        let lanes: Set<Lane>
        let connections: Int
        let wakeChanges: Int
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let agent = detail?.agent {
                        StateStrip(agent: agent, lanes: lanes, nameOf: nameOf)
                    }
                    if let status = detail?.agent.running.status, let unreadable = status.tasksUnreadable {
                        problem("Helper tasks could not be read: \(unreadable)")
                    }
                    if !tasks.isEmpty {
                        HelperTasks(hath: services.hath, nas: services.nas, owner: name, tasks: tasks) { await loadHost() }
                    }
                    if let hostError {
                        problem("Couldn't read the agent's tasks: \(hostError)")
                    }
                    WakeTimeline(hath: services.hath, agentId: agentId, nameOf: nameOf, selectAgent: selectAgent, refresh: .init(connections: connections, wakeChanges: wakeChanges))
                    schedulesSection
                    if let detailError {
                        problem("Couldn't load agent detail: \(detailError)")
                    }
                    if let agent = detail?.agent {
                        AboutSection(agent: agent, nameOf: nameOf, selectAgent: selectAgent)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
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
        .task(id: connections) { await loadSchedules() }
        .task(id: Reload(lanes: lanes, connections: connections, wakeChanges: wakeChanges)) { await loadDetail() }
        .task(id: live?.nas) { await loadHost() }
    }

    /// The agent's name and one summary line, with the orb of its state: processing plays the flowing dots,
    /// working is sage, and an idle or retired agent sits quiet. Open thread goes to its conversation.
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                orb.frame(width: 14, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.title3.weight(.semibold)).foregroundStyle(.ink).textSelection(.enabled)
                    if let agent = detail?.agent {
                        Text(AgentState.summary(agent, lanes: lanes, tasks: tasks.count)).font(.footnote).foregroundStyle(.inkMuted).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .laneSheen(lanes.contains(.work), in: .rect(cornerRadius: 12))
            .animation(Motion.settle, value: lanes)
            Button(action: openThread) {
                Text("Open thread").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(.sageDeep)
            .buttonBorderShape(.capsule)
        }
    }

    @ViewBuilder
    private var orb: some View {
        if lanes.contains(.process) {
            ProcessingMark()
        } else {
            Circle()
                .fill(lanes.contains(.work) ? Color.sage : .inkFaint)
                .frame(width: 10, height: 10)
        }
    }

    /// The schedules behind a disclosure: their count, none, or that they could not be read.
    private var schedulesSection: some View {
        SheetDisclosure(title: "Schedules", summary: scheduleSummary, isOpen: $schedulesOpen) {
            if let scheduleError {
                problem("Couldn't load schedules: \(scheduleError)")
            } else if let schedules, !schedules.isEmpty {
                ScheduleSection(hath: services.hath, agentId: agentId, schedules: schedules, nameOf: nameOf, changed: loadSchedules)
                    .padding(.bottom, 12)
            } else if schedules != nil {
                Text("Nothing scheduled.").font(.footnote).foregroundStyle(.inkMuted).padding(.bottom, 12)
            } else {
                SkeletonRows(count: 1, height: 14).padding(.bottom, 12)
            }
        }
    }

    private var scheduleSummary: String {
        if scheduleError != nil { return "Unavailable" }
        guard let schedules else { return "" }
        return schedules.isEmpty ? "None" : String(schedules.count)
    }

    private func problem(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.danger)
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
