import Dadi
import Foundation
import NetworkExtension
import os
import Security

/// The dadi packet-tunnel provider shared by the Mac system extension and the
/// iPhone app extension. It runs dadi's node on the tunnel and applies the
/// addresses, peer routes and `*.dadi` DNS the node reports.
open class PacketTunnelProvider: NEPacketTunnelProvider {
    /// Keys the app writes into `providerConfiguration`.
    public enum ConfigKey {
        public static let controlURL = "control_url"
        public static let hostname = "hostname"
        public static let appGroup = "app_group"
        public static let keychainGroup = "keychain_group"
    }

    /// The Keychain item holding the device's auth key from its setup code.
    public enum AuthKeyItem {
        public static let service = "com.dadi.tunnel"
        public static let account = "auth_key"
    }

    /// Messages the app sends through `sendProviderMessage`.
    public enum AppMessage {
        public static let status = Data("status".utf8)
    }

    private static let mtu: NSNumber = 1280
    private static let magicDNS = "100.100.100.100"

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.dadi.tunnel", category: "tunnel")
    private let settingsQueue = DispatchQueue(label: "com.dadi.tunnel.settings")
    private var tunnelRemoteAddress = ""

    open override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        do {
            let config = try nodeConfig()
            tunnelRemoteAddress = try controlHost(config["control_url"] ?? "")
            let json = try JSONSerialization.data(withJSONObject: config)
            guard let text = String(data: json, encoding: .utf8) else {
                throw TunnelError.config("node config is not UTF-8")
            }
            let context = Unmanaged.passUnretained(self).toOpaque()
            let result = text.withCString { dadi_start(UnsafeMutablePointer(mutating: $0), onRoutes, onChange, onLog, context) }
            if result != 0 {
                throw TunnelError.node(Self.lastError())
            }
            completionHandler(nil)
        } catch {
            log.error("start failed: \(error.localizedDescription, privacy: .public)")
            completionHandler(error)
        }
    }

    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        dadi_stop()
        completionHandler()
    }

    open override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard messageData == AppMessage.status else {
            log.error("unknown app message")
            completionHandler?(Self.errorJSON(type: "unknown_message", message: "the tunnel only answers status"))
            return
        }
        guard let status = dadi_status() else {
            let reason = Self.lastError()
            log.error("status failed: \(reason, privacy: .public)")
            completionHandler?(Self.errorJSON(type: "node_not_running", message: reason))
            return
        }
        defer { dadi_free(status) }
        completionHandler?(Data(String(cString: status).utf8))
    }

    /// Builds the node config from the VPN configuration, the app group and the Keychain.
    private func nodeConfig() throws -> [String: String] {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let provider = proto.providerConfiguration else {
            throw TunnelError.config("the VPN configuration has no provider configuration")
        }
        func required(_ key: String) throws -> String {
            guard let value = provider[key] as? String, !value.isEmpty else {
                throw TunnelError.config("\(key) is missing from the VPN configuration")
            }
            return value
        }
        let appGroup = try required(ConfigKey.appGroup)
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw TunnelError.config("app group \(appGroup) is not available to this extension")
        }
        return [
            "control_url": try required(ConfigKey.controlURL),
            "hostname": try required(ConfigKey.hostname),
            "auth_key": try Self.authKey(accessGroup: try required(ConfigKey.keychainGroup)),
            "state_dir": container.appendingPathComponent("tailscale", isDirectory: true).path,
        ]
    }

    /// The auth key from the shared Keychain, or an empty string when the device
    /// already has a saved node and the key was removed.
    private static func authKey(accessGroup: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AuthKeyItem.service,
            kSecAttrAccount as String: AuthKeyItem.account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
                throw TunnelError.config("the auth key in the Keychain is not text")
            }
            return key
        case errSecItemNotFound:
            return ""
        default:
            throw TunnelError.config("Keychain read failed (\(status))")
        }
    }

    private func controlHost(_ controlURL: String) throws -> String {
        guard let host = URL(string: controlURL)?.host, !host.isEmpty else {
            throw TunnelError.config("control_url has no host")
        }
        return host
    }

    /// Applies the node's addresses and IPv4 peer routes, with `*.dadi` resolved by MagicDNS.
    fileprivate func apply(routesJSON: String) {
        settingsQueue.async { [self] in
            guard let data = routesJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(RouteSettings.self, from: data) else {
                log.error("unreadable route settings: \(routesJSON, privacy: .public)")
                return
            }
            let addresses = decoded.localAddrs.compactMap(IPv4Prefix.init).filter { $0.bits == 32 }
            guard !addresses.isEmpty else {
                return
            }
            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: tunnelRemoteAddress)
            let ipv4 = NEIPv4Settings(addresses: addresses.map(\.address), subnetMasks: addresses.map(\.mask))
            ipv4.includedRoutes = decoded.routes.compactMap(IPv4Prefix.init).map {
                NEIPv4Route(destinationAddress: $0.address, subnetMask: $0.mask)
            }
            settings.ipv4Settings = ipv4
            let dns = NEDNSSettings(servers: [Self.magicDNS])
            dns.matchDomains = ["dadi"]
            settings.dnsSettings = dns
            settings.mtu = Self.mtu
            let done = DispatchSemaphore(value: 0)
            setTunnelNetworkSettings(settings) { [log] error in
                if let error {
                    log.error("applying tunnel settings failed: \(error.localizedDescription, privacy: .public)")
                }
                done.signal()
            }
            done.wait()
        }
    }

    fileprivate func logLine(_ line: String) {
        log.info("\(line, privacy: .public)")
    }

    fileprivate func stateChanged() {
        reasserting = false
    }

    /// An app-message reply in the services' `{error:{type,message}}` shape.
    private static func errorJSON(type: String, message: String) -> Data {
        let body = ["error": ["type": type, "message": message]]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            preconditionFailure("a dictionary of strings always serializes")
        }
        return data
    }

    private static func lastError() -> String {
        guard let message = dadi_last_error() else {
            return "unknown node error"
        }
        defer { dadi_free(message) }
        return String(cString: message)
    }
}

/// NetworkExtension drives the provider from its own queues and the node calls
/// back from Go threads; mutable state is confined to `settingsQueue`.
extension PacketTunnelProvider: @unchecked Sendable {}

/// A failure starting the tunnel, shown to the user by the app.
public enum TunnelError: LocalizedError {
    case config(String)
    case node(String)

    public var errorDescription: String? {
        switch self {
        case .config(let message): return "dadi tunnel configuration: \(message)"
        case .node(let message): return "dadi could not start: \(message)"
        }
    }
}

/// The JSON the node sends to `on_routes`.
private struct RouteSettings: Decodable {
    let localAddrs: [String]
    let routes: [String]

    enum CodingKeys: String, CodingKey {
        case localAddrs = "local_addrs"
        case routes
    }
}

/// An IPv4 CIDR as NetworkExtension wants it: address and dotted mask.
private struct IPv4Prefix {
    let address: String
    let bits: Int

    init?(_ cidr: String) {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let bits = Int(parts[1]), (0...32).contains(bits) else {
            return nil
        }
        let octets = parts[0].split(separator: ".")
        guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) else {
            return nil
        }
        self.address = String(parts[0])
        self.bits = bits
    }

    var mask: String {
        let value: UInt32 = bits == 0 ? 0 : UInt32.max << (32 - UInt32(bits))
        return [24, 16, 8, 0].map { String((value >> UInt32($0)) & 0xff) }.joined(separator: ".")
    }
}

private func provider(_ context: UnsafeMutableRawPointer?) -> PacketTunnelProvider {
    Unmanaged<PacketTunnelProvider>.fromOpaque(context!).takeUnretainedValue()
}

private let onRoutes: dadi_text_fn = { context, text in
    provider(context).apply(routesJSON: String(cString: text!))
}

private let onChange: dadi_change_fn = { context in
    provider(context).stateChanged()
}

private let onLog: dadi_text_fn = { context, text in
    provider(context).logLine(String(cString: text!))
}
