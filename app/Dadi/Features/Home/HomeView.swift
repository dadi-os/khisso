import SwiftUI

/// Home: dadi's pages in the dock, with Chats and every agent thread
/// live from Hath, and the drawer beside them (PhoneHome). Home owns the event
/// stream that keeps threads, what each agent is doing and the open thread current.
struct HomeView: View {
    /// The page Home shows.
    enum Page: Hashable {
        case dadi
        case thread(String)
        case planner
        case ghar
        case chaavi
        case system

        /// The dock tab the page belongs to; a thread is Dadi's.
        var tab: Tab {
            switch self {
            case .dadi, .thread: .dadi
            case .planner: .planner
            case .ghar: .ghar
            case .chaavi: .chaavi
            case .system: .system
            }
        }

        var isThread: Bool {
            if case .thread = self { true } else { false }
        }
    }

    /// The dock's five tabs.
    enum Tab: Hashable {
        case dadi, planner, ghar, chaavi, system

        /// The page a tab opens on.
        var home: Page {
            switch self {
            case .dadi: .dadi
            case .planner: .planner
            case .ghar: .ghar
            case .chaavi: .chaavi
            case .system: .system
            }
        }
    }

    let services: Services
    /// False while dadi is out of reach and Home shows what it last reported.
    let online: Bool

    @State private var store = HomeStore()
    @State private var live = LiveData()
    @State private var page: Page = .dadi
    /// Bumped each time the app comes forward, which reopens the event stream
    /// at once instead of trusting a connection iOS may have dropped.
    @State private var stream = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        PhoneHome(services: services, store: store, online: online, page: $page)
        .environment(live)
        .task { await store.load(services.hath) }
        .task(id: stream) { await store.follow(services.hath) }
        .task(id: stream) { await live.follow(services) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { stream += 1 }
        }
    }
}

/// One agent thread in a list, led by its name as in thaali: its name, when, and its last line, which gives way
/// to the agent's state while it works or waits. A thread with replies not yet read shows their count, its name
/// bolder. The state dot leads the name: sage and pulsing for working, a tide ring for waiting, a late ring for an
/// overdue or stopped job; an agent at rest shows none. Agents carry no color of their own.
struct ThreadRow: View {
    let thread: ThreadSummary
    let running: AgentRecord.Running
    let unread: Int
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if running.state != .idle || running.mark(at: now) != nil {
                        StateDot(state: running.state, mark: running.mark(at: now))
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                            .transition(.opacity)
                    }
                    Text(thread.agentName)
                        .font(.subheadline.weight(unread > 0 ? .bold : .semibold))
                        .foregroundStyle(.ink)
                        .lineLimit(1)
                    if let mark = running.mark(at: now) {
                        Text(mark.word).font(.caption2.weight(.medium)).foregroundStyle(Color.lateInk)
                    }
                    Spacer(minLength: 6)
                    Text(thread.lastAt, format: .relative(presentation: .named, unitsStyle: .narrow))
                        .font(.caption2)
                        .foregroundStyle(unread > 0 ? Color.sageText : .inkFaint)
                }
                Text(ChatGroups.line(thread, running: running, now: now))
                    .font(.footnote)
                    .foregroundStyle(unread > 0 ? Color.ink : .inkMuted)
                    .lineLimit(1)
            }
            if unread > 0 {
                UnreadBadge(count: unread)
            }
        }
        .animation(Motion.settle, value: running.state)
        .animation(Motion.pop, value: unread)
        .contentShape(.rect)
    }
}

/// A wake that ended failed; its timeline has the reason.
struct WakeFailure: Identifiable, Equatable {
    let id = UUID()
    let agentId: String
}

/// A router run that failed, with its own message.
struct RouterFailure: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

/// Threads, what each agent is doing and live messages for Home, fed by GET /threads, GET /agents and Hath's
/// event stream.
@MainActor
@Observable
final class HomeStore {
    private(set) var threads: [ThreadSummary] = []
    /// Every agent as Hath last listed it, its `running` moved by wake events between reads.
    private(set) var agents: [String: AgentRecord] = [:]
    /// What each running wake has done so far, from `wake_activity`.
    private(set) var liveCounts: [String: WakeCounts] = [:]
    /// The router runs in flight, by id: runs overlap, so the router is active while any is.
    private(set) var routerRuns: Set<String> = []
    /// The newest router failure, so a device that did not send the words can say so.
    private(set) var routerFailure: RouterFailure?
    /// The newest message from the event stream, for the open thread to pick up.
    private(set) var live: HathEvent?
    /// Bumped each time the event stream connects. The stream does not replay
    /// what happened while it was down, so the open thread reloads on it.
    private(set) var connections = 0
    /// Per agent, bumped on each wake event, so an open agent sheet reads its wakes again.
    private(set) var wakeChanges: [String: Int] = [:]
    /// Bumped when a routine or reminder changes, so an open agent sheet reads them again.
    private(set) var scheduleChanges = 0
    /// The newest wake that failed, so the app can say whose run it was.
    private(set) var wakeFailure: WakeFailure?
    private(set) var error: String?
    /// Why the router's runs could not be read; shown as a toast, not as the chats' error.
    private(set) var sideProblem: String?
    /// True once the threads have been read at least once.
    private(set) var loaded = false
    /// Why live updates stopped; cleared when the stream delivers again.
    private(set) var liveError: String?

    /// True while the router is choosing whom Ankur's words go to.
    var routing: Bool { !routerRuns.isEmpty }

    /// Loads the router runs already in flight, for a connection that opens mid-run.
    func loadRouter(_ hath: HathClient) async {
        do {
            routerRuns = Set(try await hath.routerRuns().map(\.runId))
        } catch {
            sideProblem = "Couldn't read the router: \(error.localizedDescription)"
        }
    }

    /// Each agent's messages as last read, so a thread opens already laid out instead of filling in during its push.
    private(set) var history: [String: [DurableMessage]] = [:]

    /// Reads `agentId`'s messages ahead of its thread opening. A failure is left to the thread, which reads again and shows why.
    func preloadThread(_ hath: HathClient, agentId: String) async {
        if let messages = try? await hath.messages(agentId: agentId) {
            history[agentId] = messages.shown
        }
    }

    /// Loads every thread.
    func load(_ hath: HathClient) async {
        do {
            threads = try await hath.threads()
            loaded = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Follows Hath's events until the view goes away. Each connect reloads the
    /// threads and agents and bumps `connections`, since the stream does not
    /// replay; a dropped or silent stream is reported and reopened after a
    /// short, growing delay, up to 30 s.
    func follow(_ hath: HathClient) async {
        var delay: Duration = .seconds(1)
        while !Task.isCancelled {
            do {
                let events = try await hath.events()
                try await loadAgents(hath)
                await load(hath)
                await loadRouter(hath)
                connections += 1
                for try await event in events {
                    delay = .seconds(1)
                    liveError = nil
                    await apply(event, hath)
                }
            } catch is CancellationError {
                return
            } catch {
                liveError = "Live updates stopped: \(error.localizedDescription)"
            }
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            delay = min(delay * 2, .seconds(30))
        }
    }

    /// Tells Hath that Ankur has read `agentId`'s thread through `seq`, so every
    /// device clears it, and clears it here at once.
    func markRead(_ hath: HathClient, agentId: String, through seq: Int) async {
        guard let thread = threads.first(where: { $0.agentId == agentId }), thread.readSeq.map({ $0 < seq }) ?? true else { return }
        do {
            let mark = try await hath.markRead(agentId, through: seq)
            setRead(agentId, readSeq: mark.readSeq, unread: mark.unread)
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn't mark \(agentId) read: \(error.localizedDescription)"
        }
    }

    private func setRead(_ agentId: String, readSeq: Int, unread: Int) {
        guard let index = threads.firstIndex(where: { $0.agentId == agentId }) else { return }
        threads[index].readSeq = readSeq
        threads[index].unread = unread
    }

    /// Reads the roster, replacing what each agent is doing with what Hath reports.
    func loadAgents(_ hath: HathClient) async throws {
        let listed = try await hath.agents()
        agents = Dictionary(uniqueKeysWithValues: listed.map { ($0.id, $0) })
        liveCounts = liveCounts.filter { agents[$0.key]?.running.working == true }
    }

    /// Reads the roster again, saying why it could not be read.
    func refreshAgents(_ hath: HathClient) async {
        do {
            try await loadAgents(hath)
        } catch is CancellationError {
            return
        } catch {
            sideProblem = "Couldn't read the agents: \(error.localizedDescription)"
        }
    }

    /// Whether `agentId` is an agent that can still be messaged.
    func isActive(_ agentId: String) -> Bool { agents[agentId]?.active == true }

    /// What `agentId` is doing; at rest for an agent not listed.
    func running(of agentId: String) -> AgentRecord.Running { agents[agentId]?.running ?? .quiet }

    /// What the wake running now on `agentId` has done so far.
    func counts(of agentId: String) -> WakeCounts? { liveCounts[agentId] }

    private func setWorking(_ agentId: String, _ working: Bool) {
        guard var agent = agents[agentId] else { return }
        agent.running = AgentRecord.Running(working: working, waitingOn: agent.running.waitingOn, job: agent.running.job)
        agents[agentId] = agent
    }

    /// The display name of an agent's thread; the id until the thread is known.
    func name(of agentId: String) -> String {
        threads.first { $0.agentId == agentId }?.agentName ?? agentId
    }

    private func apply(_ event: HathEvent, _ hath: HathClient) async {
        switch event {
        case .message(_, let message):
            live = event
            await load(hath)
            if !message.fromUser { await refreshAgents(hath) }
        case .threadRead(let agentId, let readSeq, let unread):
            setRead(agentId, readSeq: readSeq, unread: unread)
        case .wakeStarted(let agentId, _):
            setWorking(agentId, true)
            liveCounts[agentId] = WakeCounts.none
            wakeChanges[agentId, default: 0] += 1
            await refreshAgents(hath)
        case .wakeActivity(let agentId, _, let counts):
            liveCounts[agentId] = counts
        case .wakeEnded(let agentId, _, let outcome):
            setWorking(agentId, false)
            liveCounts[agentId] = nil
            wakeChanges[agentId, default: 0] += 1
            if outcome == .failed { wakeFailure = WakeFailure(agentId: agentId) }
            await refreshAgents(hath)
        case .schedulesChanged:
            scheduleChanges += 1
        case .routerStarted(let runId):
            routerRuns.insert(runId)
        case .routerFinished(let runId):
            routerRuns.remove(runId)
        case .routerFailed(let runId, let message):
            routerRuns.remove(runId)
            routerFailure = RouterFailure(message: message)
        case .unhandled:
            break
        }
    }
}
