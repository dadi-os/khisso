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
    /// When an online connection stopped hearing from dadi; nil while online or
    /// before it has ever been online. Home stays on screen, dimmed, while set.
    private(set) var offlineSince: Date?

    private var node: InAppNode?
    private var checking = false
    /// The node changed while a check was running, so another follows it.
    private var recheck = false
    /// Health checks missed in a row while online.
    private var misses = 0
    /// When Hath last stopped answering; nil while it answers.
    private var unansweredSince: ContinuousClock.Instant?

    /// How often an online connection checks Hath, and how long one check waits.
    private static let onlineEvery: Duration = .seconds(10)
    private static let onlineTimeout: TimeInterval = 6
    /// How often a connection that is not online yet checks Hath, and how long
    /// one check waits: short, so the moment the node can reach the box the
    /// app is online, not one backoff later.
    private static let connectingEvery: Duration = .seconds(1)
    private static let connectingTimeout: TimeInterval = 3
    /// How often a node that failed to start is started again.
    private static let failedEvery: Duration = .seconds(5)
    /// Checks missed in a row before an online connection says it is reconnecting.
    private static let allowedMisses = 2
    /// How long Hath may be quiet while connecting before the screen says so.
    private static let quietBeforeSaying: Duration = .seconds(5)
    /// How long Hath may be quiet before the node is restarted.
    private static let restartAfter: Duration = .seconds(60)
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

    /// Checks Hath until cancelled: every ten seconds while online and every
    /// second while not, restarting a node that failed to start, or one Hath
    /// has not answered through for a minute.
    func watch() async {
        while !Task.isCancelled {
            let wait: Duration
            switch state {
            case .needsSetup:
                wait = Self.connectingEvery
            case .failed:
                retry()
                wait = Self.failedEvery
            case .connecting, .online:
                if let since = unansweredSince, ContinuousClock.now - since >= Self.restartAfter {
                    log.info("restarting the node after a minute without an answer from Hath")
                    unansweredSince = nil
                    misses = 0
                    retry()
                }
                await check()
                wait = state == .online ? Self.onlineEvery : Self.connectingEvery
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
        unansweredSince = nil
        misses = 0
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

    /// Asks Hath for `/health`. A check asked for while one runs is not
    /// dropped: it runs as soon as that one ends, so the node coming up mid-check
    /// is noticed at once. While connecting, a miss is only spoken after a few
    /// quiet seconds; while online it is forgiven until `allowedMisses` in a
    /// row, since one dropped request is not a lost box.
    private func check() async {
        guard let hath = services?.hath else { return }
        guard !checking else {
            recheck = true
            return
        }
        checking = true
        defer { checking = false }
        repeat {
            recheck = false
            let online = state == .online
            do {
                _ = try await hath.health(timeout: online ? Self.onlineTimeout : Self.connectingTimeout)
                misses = 0
                unansweredSince = nil
                offlineSince = nil
                state = .online
            } catch is CancellationError {
                return
            } catch {
                misses += 1
                let since = unansweredSince ?? .now
                unansweredSince = since
                log.error("hath health: \(error.localizedDescription, privacy: .public)")
                if online {
                    if misses >= Self.allowedMisses {
                        offlineSince = .now
                        state = .connecting(detail: "dadi isn't answering: \(error.localizedDescription)")
                    }
                } else if ContinuousClock.now - since >= Self.quietBeforeSaying {
                    state = .connecting(detail: "dadi isn't answering yet: \(error.localizedDescription)")
                }
            }
        } while recheck && state != .online
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
