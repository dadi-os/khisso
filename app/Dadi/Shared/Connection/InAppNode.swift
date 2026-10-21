import Dadi
import Foundation
import Network
import os

/// dadi's node running inside the app (Dadi.xcframework's dadi_app_* calls).
/// Only the app's own traffic reaches dadi, through the node's loopback
/// CONNECT proxy; `session` is the URLSession wired to it.
final class InAppNode: @unchecked Sendable {
    /// The node's state as the app shows it (node.Status in Go).
    struct Status: Decodable, Sendable, Equatable {
        struct Peer: Decodable, Sendable, Equatable {
            let name: String
            let ip: String
            let online: Bool
        }

        let backendState: String
        let hostname: String
        let selfIp: String
        let peers: [Peer]
        let lastError: String

        var running: Bool { backendState == "Running" }
    }

    /// Why the node failed, in its own words.
    struct NodeError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let log = Logger(subsystem: "com.dadi.khisso", category: "node")

    private let onChange: @Sendable () -> Void
    private(set) var session: URLSession!

    private init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    /// Starts the node with `code` and its state under `stateDirectory`.
    /// `onChange` runs on a node thread whenever its state, peers or last error
    /// change.
    static func start(code: SetupCode, stateDirectory: URL, onChange: @escaping @Sendable () -> Void) throws -> InAppNode {
        let node = InAppNode(onChange: onChange)
        let config: [String: String] = [
            "control_url": code.controlUrl,
            "hostname": code.nodeName,
            "auth_key": code.authKey,
            "state_dir": stateDirectory.path,
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: config), as: UTF8.self)
        let context = Unmanaged.passUnretained(node).toOpaque()
        let port = json.withCString { dadi_app_start(UnsafeMutablePointer(mutating: $0), nodeChanged, nodeLog, context) }
        guard port > 0, let proxyPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw NodeError(message: lastError())
        }
        var proxy = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: "127.0.0.1", port: proxyPort))
        proxy.allowFailover = false
        let configuration = URLSessionConfiguration.default
        configuration.proxyConfigurations = [proxy]
        configuration.waitsForConnectivity = false
        node.session = URLSession(configuration: configuration)
        return node
    }

    /// The node's current status.
    func status() throws -> Status {
        guard let raw = dadi_app_status() else {
            throw NodeError(message: Self.lastError())
        }
        defer { dadi_free(raw) }
        return try JSONDecoder.snakeCase.decode(Status.self, from: Data(String(cString: raw).utf8))
    }

    /// Stops the node and its proxy.
    func stop() {
        session.invalidateAndCancel()
        dadi_app_stop()
    }

    fileprivate func changed() { onChange() }

    fileprivate static func record(_ line: String) {
        log.info("\(line, privacy: .public)")
    }

    /// dadi_last_error's message; the library always returns a string.
    private static func lastError() -> String {
        let raw = dadi_last_error()!
        defer { dadi_free(raw) }
        return String(cString: raw)
    }
}

private extension JSONDecoder {
    static let snakeCase: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

private let nodeChanged: dadi_change_fn = { context in
    Unmanaged<InAppNode>.fromOpaque(context!).takeUnretainedValue().changed()
}

private let nodeLog: dadi_text_fn = { _, text in
    InAppNode.record(String(cString: text!))
}
