import Foundation
import Observation
import os

/// This device's connection to dadi: its setup code, the in-app node, and
/// whether Hath answers through it.
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
        /// The node could not start or Hath failed; `message` says why.
        case failed(message: String)
    }

    private(set) var state: State = .connecting(detail: nil)
    /// Hath over this device's node; set once the node is running.
    private(set) var hath: HathClient?
    /// This device's name on dadi.
    private(set) var nodeName: String?

    private var node: InAppNode?
    private var checking = false
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
        hath = HathClient(session: started.session)
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

    /// Asks Hath for `/health`; one check runs at a time.
    private func checkHath() {
        guard let hath, !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            do {
                _ = try await hath.health()
                state = .online
            } catch {
                fail(error)
            }
        }
    }

    private func stopNode() {
        node?.stop()
        node = nil
        hath = nil
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
