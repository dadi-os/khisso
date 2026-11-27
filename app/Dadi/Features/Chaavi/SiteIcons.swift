import SwiftUI
import UIKit

/// The site icons Chaavi's own proxy serves, one request per domain for as long as the app lives. The proxy answers a
/// site it cannot reach with a generic image; that, a failure, and an item with no domain all read as "no icon", and
/// the caller keeps its letter tile. A failed read is asked again next time rather than remembered.
@MainActor
@Observable
final class SiteIcons {
    private let fetch: @Sendable (String) async throws -> Data
    private var found: [String: Task<Data?, Never>] = [:]
    private var generic: Task<Data?, Never>?

    init(chaavi: ChaaviClient) {
        fetch = { try await chaavi.icon(of: $0) }
    }

    init(fetch: @escaping @Sendable (String) async throws -> Data) {
        self.fetch = fetch
    }

    /// The icon bytes for `domain`, or nil when Chaavi has none or could not be read.
    func icon(for domain: String) async -> Data? {
        if let task = found[domain] { return await task.value }
        let task = Task { [fetch] () -> Data? in
            do { return try await fetch(domain) } catch { return nil }
        }
        found[domain] = task
        let bytes = await task.value
        if bytes == nil { found[domain] = nil }
        guard let bytes else { return nil }
        let baseline = generic ?? Task { [fetch] () -> Data? in
            do { return try await fetch(ChaaviClient.noIconDomain) } catch { return nil }
        }
        generic = baseline
        return Self.real(bytes, generic: await baseline.value)
    }

    /// `bytes` unless they are the proxy's generic image.
    nonisolated static func real(_ bytes: Data, generic: Data?) -> Data? {
        bytes == generic ? nil : bytes
    }
}

/// An item's tile: its site's icon once Chaavi has served one, otherwise the site's first letter on its hue. The tile
/// keeps its size throughout, so nothing moves when the icon arrives.
struct SiteTile: View {
    let item: ChaaviItem
    let icons: SiteIcons
    var size: CGFloat = 42

    @State private var image: UIImage?

    var body: some View {
        let seed = item.host ?? item.name
        let hue = SiteHue.of(seed)
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().padding(size * 0.18)
            } else {
                Text(String(seed.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(hue)
            }
        }
        .frame(width: size, height: size)
        .background(image == nil ? hue.opacity(0.14) : Color.white.opacity(0.9), in: .rect(cornerRadius: size * 0.29, style: .continuous))
        .animation(Motion.snap, value: image == nil)
        .accessibilityHidden(true)
        .task(id: item.siteDomain) {
            guard let domain = item.siteDomain else { return }
            image = await icons.icon(for: domain).flatMap(UIImage.init(data:))
        }
    }
}

/// A site's color for its letter tile, the same every time: sage, clay or tide.
enum SiteHue {
    static func of(_ site: String) -> Color {
        let palette: [Color] = [.sageDeep, .clay, .tide]
        let sum = site.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }
}
