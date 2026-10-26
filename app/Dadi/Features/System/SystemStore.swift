import Foundation

/// The box as the System page and its drawer share it: its status, every
/// device on dadi but the box, and the latest errors in the logs. The page
/// reads it on its own pace while it is open.
@MainActor
@Observable
final class SystemStore {
    /// The box's own node, which is the box itself rather than a device on it.
    private static let boxNode = "os"

    /// How many recent errors the page lists.
    private static let errorCount = 8

    let nas: NasClient

    private(set) var status: NasStatus?
    private(set) var devices: [NasClientDevice] = []
    private(set) var errors: [NasLogEntry] = []
    private(set) var problem: String?

    init(nas: NasClient) {
        self.nas = nas
    }

    /// True while every module's health check passes.
    var healthy: Bool {
        guard let status else { return false }
        return status.services.allSatisfy(\.healthy)
    }

    /// Reads the box's status and the devices, online first.
    func load() async {
        do {
            async let nextStatus = nas.status()
            async let nextDevices = nas.devices()
            let (s, d) = try await (nextStatus, nextDevices)
            status = s
            devices = d.filter { $0.nodeName != Self.boxNode }.sorted { ($0.online ? 0 : 1, $0.nodeName) < ($1.online ? 0 : 1, $1.nodeName) }
            problem = nil
        } catch is CancellationError {
            return
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Reads the latest errors in the logs.
    func loadErrors() async {
        do {
            errors = try await nas.logs(level: "error", limit: Self.errorCount)
        } catch is CancellationError {
            return
        } catch {
            problem = error.localizedDescription
        }
    }
}
