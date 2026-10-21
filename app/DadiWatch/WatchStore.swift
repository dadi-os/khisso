import Foundation
import Observation
import WatchConnectivity

/// The watch's view of dadi, all through the iPhone: the last snapshot it
/// sent, kept on the watch so the app opens on it at once, and the state of
/// words handed to Dadi or an agent. The watch never polls; it asks once when
/// the app comes forward and the iPhone takes it from there.
@MainActor
@Observable
final class WatchStore: NSObject {
    /// Where words handed to Dadi are.
    enum Handoff: Equatable {
        case idle
        /// On their way to the iPhone.
        case sending
        /// The iPhone has them and the router is choosing whom they go to.
        case routing
        case sent(to: String)
        case failed(String)
    }

    private(set) var snapshot: WatchSnapshot?
    private(set) var handoff: Handoff = .idle
    /// Why the last request did not get through.
    private(set) var problem: String?
    private(set) var reachable = false

    private static let saved = "snapshot"

    override init() {
        super.init()
        guard let data = UserDefaults.standard.data(forKey: Self.saved) else { return }
        do {
            snapshot = try WatchLink.decoder.decode(WatchSnapshot.self, from: data)
        } catch {
            UserDefaults.standard.removeObject(forKey: Self.saved)
            problem = "The saved view of dadi couldn't be read; it comes back when your iPhone is nearby."
        }
    }

    func activate() {
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Asks the iPhone for a fresh snapshot.
    func refresh() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([WatchLink.op: WatchLink.refresh]) { [weak self] answer in
            let data = answer[WatchLink.snapshot] as? Data
            let error = answer[WatchLink.error] as? String
            Task { @MainActor in
                if let data { self?.apply(data) }
                self?.problem = error
            }
        } errorHandler: { [weak self] error in
            let message = error.localizedDescription
            Task { @MainActor in self?.problem = message }
        }
    }

    /// Hands `text` to the router through the iPhone.
    func route(_ text: String) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        handoff = .sending
        request([WatchLink.op: WatchLink.route, WatchLink.text: words]) { [weak self] error in
            self?.handoff = error.map(Handoff.failed) ?? .routing
        }
    }

    /// Sends `text` to `agentId` as Ankur through the iPhone; `done` hears
    /// why it failed, or nil once it is sent.
    func reply(_ text: String, to agentId: String, done: @escaping @MainActor (String?) -> Void) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        request([WatchLink.op: WatchLink.reply, WatchLink.text: words, WatchLink.agentId: agentId], done: done)
    }

    /// Lets a finished hand-off's result go.
    func settle() {
        if case .sent = handoff { handoff = .idle }
        if case .failed = handoff { handoff = .idle }
    }

    private func request(_ message: [String: Any], done: @escaping @MainActor (String?) -> Void) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            done("Your iPhone isn't nearby.")
            return
        }
        session.sendMessage(message) { answer in
            let error = answer[WatchLink.error] as? String
            Task { @MainActor in done(error) }
        } errorHandler: { error in
            let message = error.localizedDescription
            Task { @MainActor in done(message) }
        }
    }

    private func apply(_ data: Data) {
        do {
            snapshot = try WatchLink.decoder.decode(WatchSnapshot.self, from: data)
            UserDefaults.standard.set(data, forKey: Self.saved)
        } catch {
            problem = "Your iPhone sent something this watch can't read; update both."
        }
    }

    private func routed(agentName: String?, error: String?) {
        if let error {
            handoff = .failed(error)
        } else if let agentName {
            handoff = .sent(to: agentName)
        }
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext[WatchLink.snapshot] as? Data
        let reachable = session.isReachable
        let problem = error?.localizedDescription
        Task { @MainActor in
            if let data { self.apply(data) }
            self.reachable = reachable
            if let problem { self.problem = problem }
            self.refresh()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.reachable = reachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchLink.snapshot] as? Data else { return }
        Task { @MainActor in self.apply(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        receive(userInfo)
    }

    private nonisolated func receive(_ message: [String: Any]) {
        guard message[WatchLink.op] as? String == WatchLink.routed else { return }
        let name = message[WatchLink.name] as? String
        let error = message[WatchLink.error] as? String
        Task { @MainActor in self.routed(agentName: name, error: error) }
    }
}
