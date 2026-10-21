#if os(iOS)
import UIKit
import WatchConnectivity
import os

/// The iPhone's side of the watch, which has no network of its own: it
/// answers the watch's requests through this phone's connection to dadi and
/// sends it a snapshot when asked or when this app comes forward, only when
/// something changed. If the watch wakes the app while its node is down, the
/// relay starts the node and waits for Hath under a background task.
@MainActor
final class WatchRelay: NSObject {
    /// A request from the watch, read off its message.
    private enum Request: Sendable {
        case refresh
        case route(String)
        case reply(String, to: String)
    }

    /// Why the relay could not answer.
    private struct Refused: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The watch's reply handler, called once with the answer.
    private struct Reply: @unchecked Sendable {
        let send: ([String: Any]) -> Void
    }

    /// How long a request waits for this phone to reach dadi.
    private static let onlineWait: Duration = .seconds(20)

    private let connection: Connection
    private var sent: WatchSnapshot?
    private let log = Logger(subsystem: "com.dadi.khisso", category: "watch")

    init(connection: Connection) {
        self.connection = connection
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends the watch a fresh snapshot as its application context, unless it
    /// would say what the last one said.
    func push() async {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            let snapshot = try await build()
            if let sent, sent.today == snapshot.today, sent.threads == snapshot.threads, sent.box == snapshot.box { return }
            try session.updateApplicationContext([WatchLink.snapshot: try WatchLink.encoder.encode(snapshot)])
            sent = snapshot
        } catch {
            log.error("snapshot for the watch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// dadi's services once Hath answers, starting the node if the watch woke
    /// this app without one.
    private func services() async throws -> Services {
        switch connection.state {
        case .needsSetup:
            throw Refused(message: "Your iPhone hasn't joined dadi.")
        case .failed:
            connection.retry()
        case .connecting, .online:
            if connection.services == nil { connection.start() } else { connection.refresh() }
        }
        let deadline = ContinuousClock.now + Self.onlineWait
        while ContinuousClock.now < deadline {
            if connection.state == .online, let services = connection.services { return services }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw Refused(message: "dadi didn't answer on your iPhone.")
    }

    private func build() async throws -> WatchSnapshot {
        let services = try await services()
        let start = Calendar.current.startOfDay(for: .now)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
            throw Refused(message: "Today has no end on this calendar.")
        }
        async let threads = services.hath.threads()
        async let agents = services.hath.agents()
        async let blocks = services.yaad.planner(from: start, to: end)
        async let status = services.nas.status()
        let (t, a, b, s) = try await (threads, agents, blocks, status)
        let lanes = Dictionary(uniqueKeysWithValues: a.map { ($0.id, $0.lanes) })
        return WatchSnapshot(
            at: .now,
            today: b.sorted { $0.startAt < $1.startAt }.map {
                WatchSnapshot.Block(id: $0.id, title: $0.title, symbol: PlannerLayout.symbol($0.icon), startAt: $0.startAt, endAt: $0.endAt, done: $0.doneAt != nil)
            },
            threads: t.sorted { $0.lastAt > $1.lastAt }.prefix(WatchLink.threadLimit).map { thread in
                let running = lanes[thread.agentId] ?? []
                return WatchSnapshot.Thread(
                    agentId: thread.agentId,
                    name: Agent.displayName(thread.agentName),
                    lastMessage: String(thread.lastMessage.prefix(WatchLink.messageLimit)),
                    lastAt: thread.lastAt,
                    fromUser: thread.fromUser,
                    thinking: running.contains(.conversation),
                    working: running.contains(.reasoning)
                )
            },
            box: WatchSnapshot.Box(down: s.services.filter { !$0.healthy }.map(\.name))
        )
    }

    private func handle(_ request: Request, reply: Reply) async {
        let task = UIApplication.shared.beginBackgroundTask(withName: "watch")
        defer { UIApplication.shared.endBackgroundTask(task) }
        switch request {
        case .refresh:
            do {
                let snapshot = try await build()
                sent = snapshot
                reply.send([WatchLink.snapshot: try WatchLink.encoder.encode(snapshot)])
            } catch {
                reply.send([WatchLink.error: error.localizedDescription])
            }
        case .reply(let text, let agentId):
            do {
                _ = try await services().hath.send(text, to: agentId)
                reply.send([:])
            } catch {
                reply.send([WatchLink.error: error.localizedDescription])
            }
        case .route(let text):
            let services: Services
            do {
                services = try await self.services()
            } catch {
                reply.send([WatchLink.error: error.localizedDescription])
                return
            }
            reply.send([:])
            var outcome: [String: Any] = [WatchLink.op: WatchLink.routed]
            do {
                let response = try await services.hath.route(text)
                if let first = response.messages.first {
                    outcome[WatchLink.agentId] = first.toAgentId
                    outcome[WatchLink.name] = Agent.displayName(first.toAgentId)
                } else {
                    outcome[WatchLink.error] = "Dadi didn't send this anywhere."
                }
            } catch {
                outcome[WatchLink.error] = error.localizedDescription
            }
            deliver(outcome)
            await push()
        }
    }

    /// Sends the watch `message` now if it is listening, or queued for when it is.
    private func deliver(_ message: [String: Any]) {
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [log] error in
                log.error("watch message failed: \(error.localizedDescription, privacy: .public)")
                session.transferUserInfo(message)
            }
        } else {
            session.transferUserInfo(message)
        }
    }
}

extension WatchRelay: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            Logger(subsystem: "com.dadi.khisso", category: "watch").error("watch session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// A new watch was paired; listen to it.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let reply = Reply(send: replyHandler)
        let request: Request
        switch message[WatchLink.op] as? String {
        case WatchLink.refresh:
            request = .refresh
        case WatchLink.route:
            guard let text = message[WatchLink.text] as? String else { return reply.send([WatchLink.error: "The words didn't arrive."]) }
            request = .route(text)
        case WatchLink.reply:
            guard let text = message[WatchLink.text] as? String, let agentId = message[WatchLink.agentId] as? String else {
                return reply.send([WatchLink.error: "The reply didn't arrive."])
            }
            request = .reply(text, to: agentId)
        default:
            return reply.send([WatchLink.error: "This iPhone's dadi doesn't know that request; update it."])
        }
        Task { @MainActor in await self.handle(request, reply: reply) }
    }
}
#endif
