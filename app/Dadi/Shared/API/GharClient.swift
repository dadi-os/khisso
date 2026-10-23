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

    /// GET /changes: one element per change to a device's state or the registry.
    func changes() async throws -> AsyncThrowingStream<Void, Error> {
        try await client.changes("/changes")
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

    /// PATCH /devices/:id: moves, renames or regroups a device and returns it.
    func update(_ deviceId: String, _ patch: GharDevicePatch) async throws -> GharDevice {
        try await client.patch("/devices/\(deviceId)", body: patch)
    }

    /// POST /rooms.
    func createRoom(named name: String) async throws -> GharRoom {
        try await client.post("/rooms", body: ["name": name])
    }

    /// PATCH /rooms/:id.
    func renameRoom(_ roomId: String, to name: String) async throws -> GharRoom {
        try await client.patch("/rooms/\(roomId)", body: ["name": name])
    }

    /// DELETE /rooms/:id. Ghar refuses a room that still has devices with 409.
    func deleteRoom(_ roomId: String) async throws {
        try await client.delete("/rooms/\(roomId)")
    }

    /// POST /devices/:id/command.
    func send(_ command: GharCommand, to deviceId: String) async throws {
        try await client.send("/devices/\(deviceId)/command", body: command, timeout: Self.commandTimeout)
    }
}
