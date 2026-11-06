import Foundation

/// Ghar, dadi's home: devices, tags and commands.
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

    /// PATCH /devices/:id: renames or retags a device and returns it.
    func update(_ deviceId: String, _ patch: GharDevicePatch) async throws -> GharDevice {
        try await client.patch("/devices/\(deviceId)", body: patch)
    }

    /// POST /tags: a tag holding `deviceIds`. Ghar refuses a name that exists with 409.
    func createTag(named name: String, devices deviceIds: [String]) async throws -> GharTag {
        try await client.post("/tags", body: GharTagCreate(name: name, deviceIds: deviceIds))
    }

    /// POST /tags/:id/devices: puts more devices under an existing tag.
    func add(_ deviceIds: [String], toTag tagId: String) async throws -> GharTag {
        try await client.post("/tags/\(tagId)/devices", body: GharTagDevices(deviceIds: deviceIds))
    }

    /// PATCH /tags/:id.
    func renameTag(_ tagId: String, to name: String) async throws -> GharTag {
        try await client.patch("/tags/\(tagId)", body: ["name": name])
    }

    /// DELETE /tags/:id: takes the tag off every device; the devices stay.
    func deleteTag(_ tagId: String) async throws {
        try await client.delete("/tags/\(tagId)")
    }

    /// POST /devices/:id/command.
    func send(_ command: GharCommand, to deviceId: String) async throws {
        try await client.send("/devices/\(deviceId)/command", body: command, timeout: Self.commandTimeout)
    }
}
