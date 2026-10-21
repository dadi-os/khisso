import SwiftUI

/// Home: Talk to Dadi and every agent thread, live from Hath. The iPhone shows
/// one page at a time with a drawer (PhoneHome); the Mac shows the sidebar
/// beside the page (MacHome). Home owns the event stream that keeps threads,
/// running lanes and the open thread current.
struct HomeView: View {
    /// The page Home shows.
    enum Page: Hashable {
        case dadi
        case thread(String)
        case timeline
        case ghar
        case chaavi
    }

    let services: Services
    let nodeName: String?
    let wordmark: Namespace.ID

    @State private var store = HomeStore()
    @State private var page: Page = .dadi

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

/// One agent thread in a list: the agent's initial, name, last line, when, and
/// a breathing dot while one of its lanes runs.
struct ThreadRow: View {
    let thread: ThreadSummary
    let running: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(String(thread.agentName.prefix(1)).uppercased())
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Color.bone : hue)
                .frame(width: 34, height: 34)
                .background(selected ? AnyShapeStyle(hue) : AnyShapeStyle(hue.opacity(0.16)), in: .circle)
                .overlay(alignment: .bottomTrailing) {
                    if running {
                        Circle()
                            .fill(.sage)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(Color.bone, lineWidth: 2))
                            .phaseAnimator([1.0, 0.45]) { dot, phase in dot.opacity(phase) } animation: { _ in Motion.breath }
                            .offset(x: 2, y: 2)
                    }
                }
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
                Text(running ? "Working…" : Agent.preview(thread.lastMessage))
                    .font(.footnote)
                    .foregroundStyle(running ? Color.sageText : .inkMuted)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
        }
        .animation(Motion.settle, value: running)
        .contentShape(.rect)
    }

    private var hue: Color { Agent.hue(thread.agentId) }
}

/// How agents read in lists: their ids made into names, a stable color each,
/// and a message as one plain line.
enum Agent {
    /// "finance-specialist" as "Finance specialist".
    static func displayName(_ id: String) -> String {
        let words = id.split(separator: "-").joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// The agent's color, the same every time: sage, clay or tide.
    static func hue(_ id: String) -> Color {
        let palette: [Color] = [.sageDeep, .clay, .tide]
        let sum = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }

    /// A message's first line without markdown, for previews.
    static func preview(_ content: String) -> String {
        let line = content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: line, options: options) else { return line }
        return String(parsed.characters)
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
        Agent.displayName(threads.first { $0.agentId == agentId }?.agentName ?? agentId)
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
