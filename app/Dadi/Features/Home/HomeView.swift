import SwiftUI

/// Home: the sidebar with Talk to Dadi and every agent thread, and the selected
/// page beside it (stacked on iPhone). Owns the live event stream that keeps
/// threads, running lanes and the open thread current.
struct HomeView: View {
    /// What the detail column shows.
    enum Page: Hashable {
        case dadi
        case thread(String)
    }

    let hath: HathClient
    let nodeName: String?
    let wordmark: Namespace.ID

    @State private var store = HomeStore()
    @State private var page: Page? = .dadi

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                NavigationLink(value: Page.dadi) {
                    Label("Talk to Dadi", systemImage: "sparkles")
                }
                Section("Agents") {
                    ForEach(store.threads) { thread in
                        NavigationLink(value: Page.thread(thread.agentId)) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(thread.agentName).font(.headline).lineLimit(1)
                                    if store.running.contains(thread.agentId) {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 6))
                                            .foregroundStyle(.tint)
                                            .symbolEffect(.pulse)
                                    }
                                    Spacer()
                                    Text(thread.lastAt, format: .relative(presentation: .named))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Text(thread.lastMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                if let error = store.liveError {
                    Section {
                        Label(error, systemImage: "bolt.horizontal.circle")
                            .foregroundStyle(.orange)
                    }
                }
                if let error = store.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button("Reload") { Task { await store.load(hath) } }
                    }
                }
            }
            .navigationTitle("dadi")
            .toolbar {
                if let nodeName {
                    ToolbarItem {
                        Label(nodeName, systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.secondary)
                            .help("Online as \(nodeName)")
                    }
                }
            }
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 400)
            #endif
        } detail: {
            switch page {
            case .dadi, .none:
                DadiView(hath: hath, wordmark: wordmark) { agentId in page = .thread(agentId) }
            case .thread(let agentId):
                ThreadView(hath: hath, agentId: agentId, name: store.name(of: agentId), live: store.live)
                    .id(agentId)
            }
        }
        .task { await store.load(hath) }
        .task { await store.follow(hath) }
    }
}

/// Threads, running lanes and live messages for Home, fed by GET /threads and
/// Hath's event stream.
@MainActor
@Observable
final class HomeStore {
    private(set) var threads: [ThreadSummary] = []
    /// Agents with a lane running right now.
    private(set) var running: Set<String> = []
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
                for try await event in try await hath.events() {
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

    /// The display name of an agent's thread; the id until the thread is known.
    func name(of agentId: String) -> String {
        threads.first { $0.agentId == agentId }?.agentName ?? agentId
    }

    private func apply(_ event: HathEvent, _ hath: HathClient) async {
        switch event {
        case .message:
            live = event
            await load(hath)
        case .laneStarted(let agentId):
            running.insert(agentId)
        case .laneFinished(let agentId), .laneFailed(let agentId, _):
            running.remove(agentId)
        case .routerStarted, .routerFinished, .routerFailed, .unhandled:
            break
        }
    }
}
