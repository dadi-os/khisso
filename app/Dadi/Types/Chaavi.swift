import Foundation

/// A vault item from GET /v1/items. It never carries a secret; reveals return
/// one at a time.
struct ChaaviItem: Decodable, Sendable, Hashable, Identifiable {
    /// A login website.
    struct Uri: Decodable, Sendable, Hashable {
        let uri: String
    }

    /// Login fields that are not secret, and which secrets it holds.
    struct Login: Decodable, Sendable, Hashable {
        let username: String?
        let uris: [Uri]
        let hasPassword: Bool
        let hasTotp: Bool
    }

    let id: String
    let name: String
    let favorite: Bool
    /// login, note, card, identity, sshKey, bankAccount, driversLicense or passport.
    let type: String
    let login: Login?

    /// The first website's host, for matching and showing.
    var host: String? {
        guard let raw = login?.uris.first?.uri else { return nil }
        let withScheme = raw.contains("://") ? raw : "https://\(raw)"
        return URL(string: withScheme)?.host()
    }
}

/// Body of POST /v1/items/:id/reveal.
struct ChaaviReveal: Encodable, Sendable {
    /// password, totp, number or code.
    let field: String
}

/// The current one-time code from POST /v1/items/:id/totp.
struct ChaaviTotp: Decodable, Sendable, Equatable {
    let code: String
    let period: Int
    let remaining: Int
}

/// An empty request body.
struct EmptyBody: Encodable, Sendable {}
