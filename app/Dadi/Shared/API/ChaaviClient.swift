import Foundation

/// Chaavi, dadi's passwords: the vault's items, one-at-a-time reveals, new
/// logins and notes, stars, deletes and generated passwords.
struct ChaaviClient: Sendable {
    /// Chaavi's adapter on dadi, cleartext on the mesh.
    static let baseURL = URL(string: "http://chaavi.dadi")!

    let client: ServiceClient

    init(session: URLSession) {
        client = ServiceClient(session: session, baseURL: Self.baseURL)
    }

    /// GET /v1/events: one element per change to the vault's items or folders.
    func changes() async throws -> AsyncThrowingStream<Void, Error> {
        try await client.changes("/v1/events")
    }

    /// GET /v1/items.
    func items() async throws -> [ChaaviItem] {
        struct Response: Decodable { let items: [ChaaviItem] }
        let response: Response = try await client.get("/v1/items")
        return response.items
    }

    /// GET /v1/folders.
    func folders() async throws -> [ChaaviFolder] {
        struct Response: Decodable { let folders: [ChaaviFolder] }
        let response: Response = try await client.get("/v1/folders")
        return response.folders
    }

    /// POST /v1/items: saves a new login or note and returns it.
    func create(_ item: ChaaviNewItem) async throws -> ChaaviItem {
        try await client.post("/v1/items", body: item, encoder: ServiceJSON.verbatimEncoder)
    }

    /// PATCH /v1/items/:id: stars or unstars an item.
    func setFavorite(_ favorite: Bool, of itemId: String) async throws -> ChaaviItem {
        try await client.patch("/v1/items/\(itemId)", body: ChaaviFavorite(favorite: favorite), encoder: ServiceJSON.verbatimEncoder)
    }

    /// DELETE /v1/items/:id.
    func delete(_ itemId: String) async throws {
        try await client.delete("/v1/items/\(itemId)")
    }

    /// POST /v1/generate: a new password, not stored anywhere.
    func generate(length: Int, symbols: Bool) async throws -> String {
        struct Response: Decodable { let password: String }
        let response: Response = try await client.post("/v1/generate", body: ChaaviGenerate(length: length, special: symbols), encoder: ServiceJSON.verbatimEncoder)
        return response.password
    }

    /// POST /v1/items/:id/reveal: one secret value.
    func reveal(_ field: String, of itemId: String) async throws -> String {
        struct Response: Decodable { let value: String }
        let response: Response = try await client.post("/v1/items/\(itemId)/reveal", body: ChaaviReveal(field: field))
        return response.value
    }

    /// POST /v1/items/:id/totp: the current one-time code.
    func totp(of itemId: String) async throws -> ChaaviTotp {
        try await client.post("/v1/items/\(itemId)/totp", body: EmptyBody())
    }
}
