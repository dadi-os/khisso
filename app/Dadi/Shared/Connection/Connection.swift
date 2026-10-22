import Foundation
import Observation
import os

/// This device's connection to dadi: its setup code, the in-app node, and
/// whether Hath answers through it. While the app is in front, `watch` keeps
/// asking, so a box that restarts or a node that wakes from suspension comes
/// back online without a tap.
@MainActor
@Observable
final class Connection {
    /// What the app can show and do right now.
    enum State: Equatable {
        /// No setup code saved; the Join screen asks for one.
        case needsSetup
        /// The node is logging in or Hath has not answered yet. `detail` is the
        /// node's last error while it retries.
        case connecting(detail: String?)
        /// Hath answered `/health` through the node.
        case online
        /// The node could not start; `message` says why. It is retried.
        case failed(message: String)
    }

    private(set) var state: State = .connecting(detail: nil)
    /// dadi's services over this device's node; set once the node is running.
    private(set) var services: Services?
    /// This device's name on dadi.
    private(set) var nodeName: String?

    private var node: InAppNode?
    private var checking = false
    /// Health checks missed in a row while online.
    private var misses = 0

    /// How often an online connection checks Hath.
    private static let onlineEvery: Duration = .seconds(10)
    /// The first and longest waits between checks while not online.
    private static let firstRetry: Duration = .seconds(2)
    private static let longestRetry: Duration = .seconds(15)
    /// Checks missed in a row before an online connection says it is reconnecting.
    private static let allowedMisses = 2
    /// Checks missed in a row before the node is restarted.
    private static let restartAfter = 6
    private let log = Logger(subsystem: "com.dadi.khisso", category: "connection")

    /// Loads the saved setup code and starts the node, or asks for a code.
    func start() {
        do {
            guard let code = try SetupStore.load() else {
                state = .needsSetup
                return
            }
            try run(code)
        } catch {
            fail(error)
        }
    }

    /// Saves a pasted setup code as this device's identity and joins dadi with
    /// it. Any earlier node state is removed so the code's key registers a
    /// fresh device.
    func join(pasted: String) throws {
        let code = try SetupCode(pasted: pasted)
        stopNode()
        try FileManager.default.removeItemIfPresent(at: try Self.stateDirectory())
        try SetupStore.save(code)
        try run(code)
    }

    /// Stops the node and deletes this device's setup code and node state.
    func forget() {
        stopNode()
        do {
            try SetupStore.delete()
            try FileManager.default.removeItemIfPresent(at: try Self.stateDirectory())
            state = .needsSetup
        } catch {
            fail(error)
        }
    }

    /// Restarts the node after a failure.
    func retry() {
        stopNode()
        start()
    }

    /// Checks Hath until cancelled: every ten seconds while online, and with a
    /// delay growing from two to fifteen seconds while not, restarting a node
    /// that failed to start or that six checks in a row could not get through.
    func watch() async {
        var wait = Self.firstRetry
        while !Task.isCancelled {
            switch state {
            case .needsSetup:
                wait = Self.firstRetry
            case .failed:
                retry()
                wait = min(wait * 2, Self.longestRetry)
            case .connecting, .online:
                let wasOnline = state == .online
                if misses >= Self.restartAfter {
                    log.info("restarting the node after \(self.misses) missed checks")
                    misses = 0
                    retry()
                }
                await check()
                wait = state == .online ? Self.onlineEvery : (wasOnline ? Self.firstRetry : min(wait * 2, Self.longestRetry))
            }
            do { try await Task.sleep(for: wait) } catch { return }
        }
    }

    /// Checks Hath again when the app returns to the foreground.
    func refresh() {
        guard node != nil else { return }
        nodeChanged()
    }

    private func run(_ code: SetupCode) throws {
        state = .connecting(detail: nil)
        nodeName = code.nodeName
        let started = try InAppNode.start(code: code, stateDirectory: try Self.stateDirectory()) { [weak self] in
            Task { @MainActor in self?.nodeChanged() }
        }
        node = started
        services = Services(session: started.session)
        log.info("node started as \(code.nodeName, privacy: .public)")
    }

    private func nodeChanged() {
        guard let node else { return }
        do {
            let status = try node.status()
            guard status.running else {
                state = .connecting(detail: status.lastError.isEmpty ? nil : status.lastError)
                return
            }
            checkHath()
        } catch {
            fail(error)
        }
    }

    /// Asks Hath for `/health` in the background; one check runs at a time.
    private func checkHath() {
        Task { await check() }
    }

    /// Asks Hath for `/health`. A miss while connecting says why; while online
    /// it is forgiven until `allowedMisses` in a row, since one dropped request
    /// is not a lost box.
    private func check() async {
        guard let hath = services?.hath, !checking else { return }
        checking = true
        defer { checking = false }
        do {
            _ = try await hath.health(timeout: 6)
            misses = 0
            state = .online
        } catch {
            misses += 1
            log.error("hath health: \(error.localizedDescription, privacy: .public)")
            if state != .online || misses >= Self.allowedMisses {
                state = .connecting(detail: "dadi isn't answering yet: \(error.localizedDescription)")
            }
        }
    }

    private func stopNode() {
        node?.stop()
        node = nil
        services = nil
    }

    private func fail(_ error: Error) {
        log.error("\(error.localizedDescription, privacy: .public)")
        state = .failed(message: error.localizedDescription)
    }

    /// Where the node keeps its identity: Application Support/dadi/node.
    static func stateDirectory() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appending(path: "dadi/node", directoryHint: .isDirectory)
    }
}

private extension FileManager {
    /// Removes `url`; a path that does not exist is already removed.
    func removeItemIfPresent(at url: URL) throws {
        guard fileExists(atPath: url.path) else { return }
        try removeItem(at: url)
    }
}
