import Foundation

/// Ghar, dadi's home: devices, rooms and commands.
struct GharClient: Sendable {
    /// Ghar's address on dadi, served by Caddy on the box.
    static let baseURL = URL(string: "http://ghar.dadi")!

    /// A device that does not answer makes Ghar wait before it reports 504.
    static let commandTimeout: TimeInterval = 20

    let client: ServiceClient

    init(session: URLSession) {
        client = ServiceClient(session: session, baseURL: Self.baseURL)
    }

    /// GET /devices.
    func devices() async throws -> [GharDevice] {
        struct Response: Decodable { let devices: [GharDevice] }
        let response: Response = try await client.get("/devices")
        return response.devices
    }

    /// GET /rooms.
    func rooms() async throws -> [GharRoom] {
        struct Response: Decodable { let rooms: [GharRoom] }
        let response: Response = try await client.get("/rooms")
        return response.rooms
    }

    /// POST /devices/:id/command.
    func send(_ command: GharCommand, to deviceId: String) async throws {
        try await client.send("/devices/\(deviceId)/command", body: command, timeout: Self.commandTimeout)
    }
}
