import SwiftUI

/// Home: Talk to Dadi and every agent thread, live from Hath. The iPhone shows
/// one page at a time with a drawer and opens on Talk to Dadi (PhoneHome); the
/// Mac shows the sidebar beside the page and opens on its tiles (MacHome). Home owns the event stream that keeps threads,
/// running lanes and the open thread current.
struct HomeView: View {
    /// The page Home shows.
    enum Page: Hashable {
        case dadi
        case thread(String)
        case timeline
        case ghar
        case chaavi
        case system
        #if os(macOS)
        case home
        case agents
        case memory
        #endif
    }

    let services: Services
    let nodeName: String?
    let wordmark: Namespace.ID

    @State private var store = HomeStore()
    #if os(iOS)
    @State private var page: Page = .dadi
    #else
    @State private var page: Page = .home
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            PhoneHome(services: services, wordmark: wordmark, store: store, page: $page)
            #else
            MacHome(services: services, nodeName: nodeName, wordmark: wordmark, store: store, page: $page)
            #endif
        }
        .task { await store.load(services.hath) }
        .task { await store.follow(services.hath) }
    }
}

/// One agent thread in a list: the agent's initial, name, when, and its last
/// line, which gives way to thaali's flowing dots while the agent thinks. A
/// working agent's row runs the sheen, which the list puts on the row's shape.
struct ThreadRow: View {
    let thread: ThreadSummary
    let lanes: Set<Lane>
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(String(thread.agentName.prefix(1)).uppercased())
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Color.bone : hue)
                .frame(width: 34, height: 34)
                .background(selected ? AnyShapeStyle(hue) : AnyShapeStyle(hue.opacity(0.16)), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Agent.displayName(thread.agentName))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(thread.lastAt, format: .relative(presentation: .named, unitsStyle: .narrow))
                        .font(.caption2)
                        .foregroundStyle(.inkFaint)
                }
                if lanes.contains(.conversation) {
                    ThinkingMark()
                        .frame(height: 18)
                        .transition(.opacity)
                } else {
                    Text((thread.fromUser ? "You: " : "") + Agent.preview(thread.lastMessage))
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
        }
        .animation(Motion.settle, value: lanes)
        .contentShape(.rect)
    }

    private var hue: Color { Agent.hue(thread.agentId) }
}

/// Threads, running lanes and live messages for Home, fed by GET /threads,
/// GET /agents for the lanes already running, and Hath's event stream.
@MainActor
@Observable
final class HomeStore {
    private(set) var threads: [ThreadSummary] = []
    /// Each agent's lanes running right now.
    private(set) var lanes: [String: Set<Lane>] = [:]
    /// True while the router is choosing whom Ankur's words go to.
    private(set) var routing = false
    /// The newest message from the event stream, for the open thread to pick up.
    private(set) var live: HathEvent?
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

    /// Follows Hath's events until the view goes away. A dropped stream is
    /// reported and reopened after a short, growing delay, up to 30 s.
    func follow(_ hath: HathClient) async {
        var delay: Duration = .seconds(1)
        while !Task.isCancelled {
            do {
                let events = try await hath.events()
                lanes = Dictionary(uniqueKeysWithValues: try await hath.agents().map { ($0.id, $0.lanes) }).filter { !$0.value.isEmpty }
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

    /// Agents with any lane running.
    var running: Set<String> { Set(lanes.keys) }

    /// The lanes `agentId` has running.
    func lanes(of agentId: String) -> Set<Lane> { lanes[agentId] ?? [] }

    /// The display name of an agent's thread; the id until the thread is known.
    func name(of agentId: String) -> String {
        Agent.displayName(threads.first { $0.agentId == agentId }?.agentName ?? agentId)
    }

    private func apply(_ event: HathEvent, _ hath: HathClient) async {
        switch event {
        case .message:
            live = event
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
