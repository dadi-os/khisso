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
        case tick(String, done: Bool)
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
            if let sent, sent.today == snapshot.today, sent.tasks == snapshot.tasks, sent.threads == snapshot.threads, sent.box == snapshot.box { return }
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
        async let blocks = services.yaad.plans(from: start, to: end)
        async let list = services.yaad.tasks(on: TaskLogic.key(start))
        async let status = services.nas.status()
        let (t, a, b, l, s) = try await (threads, agents, blocks, list, status)
        let groups = TaskLogic.groups(l, on: start)
        let running = Dictionary(uniqueKeysWithValues: a.map { ($0.id, $0.running) })
        let shown = t.sorted { $0.lastAt > $1.lastAt }.prefix(WatchLink.threadLimit)
        let attention = try await Self.attention(services.hath, threads: shown.filter { !$0.fromUser && running[$0.agentId]?.working != true }.prefix(WatchLink.attentionLimit).map(\.agentId))
        return WatchSnapshot(
            at: .now,
            today: WidgetLogic.tilePlans(b, on: start).compactMap { plan in
                plan.endAt.map { WatchSnapshot.Block(id: plan.id, title: plan.title, startAt: plan.startAt, endAt: $0, declined: plan.declined) }
            },
            tasks: ((groups.pastDue + groups.open).prefix(WatchLink.taskLimit) + groups.done).map { task in
                WatchSnapshot.Task(id: task.id, title: task.title, done: task.done, pastDue: !task.done && (task.pastDue || task.closesAt.map { $0 < start } == true), closesAt: task.closesAt)
            },
            threads: shown.map { thread in
                WatchSnapshot.Thread(
                    agentId: thread.agentId,
                    name: thread.agentName,
                    lastMessage: String(thread.lastMessage.prefix(WatchLink.messageLimit)),
                    lastAt: thread.lastAt,
                    fromUser: thread.fromUser,
                    state: running[thread.agentId]?.state ?? .idle,
                    attention: attention[thread.agentId],
                    unread: thread.unread
                )
            },
            box: WatchSnapshot.Box(down: s.services.filter { !$0.healthy }.map(\.name))
        )
    }

    /// What each of `agentIds` leaves open for Ankur, read from its newest messages and wakes.
    private static func attention(_ hath: HathClient, threads agentIds: [String]) async throws -> [String: WatchSnapshot.Thread.Attention] {
        try await withThrowingTaskGroup(of: (String, WatchSnapshot.Thread.Attention?).self) { group in
            for agentId in agentIds {
                group.addTask {
                    switch try await Standing.read(hath: hath, agentId: agentId)?.kind {
                    case .needsInput: (agentId, .needsInput)
                    case .blocked: (agentId, .blocked)
                    case nil: (agentId, nil)
                    }
                }
            }
            var found: [String: WatchSnapshot.Thread.Attention] = [:]
            for try await (agentId, kind) in group { found[agentId] = kind }
            return found
        }
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
        case .tick(let taskId, let done):
            do {
                _ = try await services().yaad.setDone(done, task: taskId)
                reply.send([:])
                await push()
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
                    let threads = try await services.hath.threads()
                    outcome[WatchLink.agentId] = first.toAgentId
                    outcome[WatchLink.name] = threads.first { $0.agentId == first.toAgentId }?.agentName ?? first.toAgentId
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
        case WatchLink.tick:
            guard let taskId = message[WatchLink.taskId] as? String, let done = message[WatchLink.done] as? Bool else {
                return reply.send([WatchLink.error: "The task didn't arrive."])
            }
            request = .tick(taskId, done: done)
        default:
            return reply.send([WatchLink.error: "This iPhone's dadi doesn't know that request; update it."])
        }
        Task { @MainActor in await self.handle(request, reply: reply) }
    }
}
