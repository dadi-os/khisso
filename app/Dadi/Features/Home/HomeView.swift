import SwiftUI

/// Home: Talk to Dadi and every agent thread, live from Hath, one page at a
/// time with the drawer beside it (PhoneHome). Home owns the event stream that
/// keeps threads, running lanes and the open thread current.
struct HomeView: View {
    /// The page Home shows.
    enum Page: Hashable {
        case dadi
        case thread(String)
        case timeline
        case ghar
        case chaavi
        case system
    }

    let services: Services
    let wordmark: Namespace.ID

    @State private var store = HomeStore()
    @State private var page: Page = .dadi
    /// Bumped each time the app comes forward, which reopens the event stream
    /// at once instead of trusting a connection iOS may have dropped.
    @State private var stream = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        PhoneHome(services: services, wordmark: wordmark, store: store, page: $page)
        .task { await store.load(services.hath) }
        .task(id: stream) { await store.follow(services.hath) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { stream += 1 }
        }
    }
}

/// One agent thread in a list, led by its name as in thaali: the agent's
/// color as a small dot, its name, when, and its last line, which gives way to thaali's flowing dots while the agent thinks. A
/// thread with replies not yet read shows their count, its name bolder, as in
/// thaali. A working agent's row runs the sheen, which the list puts on the
/// row's shape.
struct ThreadRow: View {
    let thread: ThreadSummary
    let lanes: Set<Lane>
    let unread: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle()
                        .fill(Agent.hue(thread.agentId))
                        .frame(width: 8, height: 8)
                    Text(thread.agentName)
                        .font(.subheadline.weight(unread > 0 ? .bold : .semibold))
                        .foregroundStyle(.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(thread.lastAt, format: .relative(presentation: .named, unitsStyle: .narrow))
                        .font(.caption2)
                        .foregroundStyle(unread > 0 ? Color.sageText : .inkFaint)
                }
                if lanes.contains(.conversation) {
                    ThinkingMark()
                        .frame(height: 18)
                        .transition(.opacity)
                } else {
                    Text((thread.fromUser ? "You: " : "") + Agent.preview(thread.lastMessage))
                        .font(.footnote)
                        .foregroundStyle(unread > 0 ? Color.ink : .inkMuted)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            if unread > 0 {
                Text("\(unread)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.bone)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(.sageDeep, in: .capsule)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("\(unread) unread")
            }
        }
        .animation(Motion.settle, value: lanes)
        .animation(Motion.pop, value: unread)
        .contentShape(.rect)
    }
}

/// Threads, running lanes and live messages for Home, fed by GET /threads,
/// GET /agents for the lanes already running, and Hath's event stream.
@MainActor
@Observable
final class HomeStore {
    private(set) var threads: [ThreadSummary] = []
    /// Each agent's lanes running right now.
    private(set) var lanes: [String: Set<Lane>] = [:]
    /// Each agent's replies that arrived while its thread was not open.
    private(set) var unread: [String: Int] = [:]
    /// The thread open now, whose replies arrive read.
    private var reading: String?
    /// True while the router is choosing whom Ankur's words go to.
    private(set) var routing = false
    /// The newest message from the event stream, for the open thread to pick up.
    private(set) var live: HathEvent?
    /// Bumped each time the event stream connects. The stream does not replay
    /// what happened while it was down, so the open thread reloads on it.
    private(set) var connections = 0
    private(set) var error: String?
    /// Why live updates stopped; cleared when the stream delivers again.
    private(set) var liveError: String?

    /// Loads every thread.
    func load(_ hath: HathClient) async {
        do {
            threads = try await hath.threads()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Follows Hath's events until the view goes away. Each connect reloads the
    /// threads and lanes and bumps `connections`, since the stream does not
    /// replay; a dropped or silent stream is reported and reopened after a
    /// short, growing delay, up to 30 s.
    func follow(_ hath: HathClient) async {
        var delay: Duration = .seconds(1)
        while !Task.isCancelled {
            do {
                let events = try await hath.events()
                lanes = Dictionary(uniqueKeysWithValues: try await hath.agents().map { ($0.id, $0.lanes) }).filter { !$0.value.isEmpty }
                await load(hath)
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

    /// Marks `agentId`'s thread as the one open, clearing its unread count;
    /// nil when no thread is open.
    func read(_ agentId: String?) {
        reading = agentId
        if let agentId { unread[agentId] = nil }
    }

    /// Agents with any lane running.
    var running: Set<String> { Set(lanes.keys) }

    /// The lanes `agentId` has running.
    func lanes(of agentId: String) -> Set<Lane> { lanes[agentId] ?? [] }

    /// The display name of an agent's thread; the id until the thread is known.
    func name(of agentId: String) -> String {
        threads.first { $0.agentId == agentId }?.agentName ?? agentId
    }

    private func apply(_ event: HathEvent, _ hath: HathClient) async {
        switch event {
        case .message(let agentId, let message):
            live = event
            if !message.fromUser, message.kind != .notice, agentId != reading {
                unread[agentId, default: 0] += 1
            }
            await load(hath)
        case .laneStarted(let agentId, let lane):
            lanes[agentId, default: []].insert(lane)
        case .laneFinished(let agentId, let lane), .laneFailed(let agentId, let lane, _):
            lanes[agentId]?.remove(lane)
            if lanes[agentId]?.isEmpty == true { lanes[agentId] = nil }
        case .routerStarted:
            routing = true
        case .routerFinished, .routerFailed:
            routing = false
        case .unhandled:
            break
        }
    }
}
