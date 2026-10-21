import Foundation

/// The dadi services a joined device talks to, all over the same connection.
struct Services: Sendable {
    let hath: HathClient
    let yaad: YaadClient
    let ghar: GharClient

    init(session: URLSession) {
        hath = HathClient(session: session)
        yaad = YaadClient(session: session)
        ghar = GharClient(session: session)
    }
}
