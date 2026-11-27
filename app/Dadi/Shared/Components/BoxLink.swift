import Foundation

/// A link to a file or folder on the box, as messages carry them: `box://` followed by the absolute path, each segment
/// percent-encoded and a trailing slash on a folder, the same as thaali writes and reads.
struct BoxLink: Hashable, Identifiable {
    /// The dadi home: the root of the box's files and of every link.
    static let home = "/var/home/dadi"

    static let scheme = "box://"

    /// Absolute, with no trailing slash except for the root.
    let path: String
    let folder: Bool

    var id: String { path }

    /// The last segment of `path`.
    var name: String { Self.baseName(path) }

    /// The link target: `box://` and the encoded path.
    var href: String {
        let encoded = path.split(separator: "/", omittingEmptySubsequences: false).map { Self.encode(String($0)) }.joined(separator: "/")
        return Self.scheme + encoded + (folder && !encoded.hasSuffix("/") ? "/" : "")
    }

    /// The Markdown a message carries: the name as the text, brackets escaped, and `href` as the target.
    var markdown: String {
        "[\(name.replacing("\\", with: "\\\\").replacing("[", with: "\\[").replacing("]", with: "\\]"))](\(href))"
    }

    init(path: String, folder: Bool) {
        self.path = path
        self.folder = folder
    }

    /// Reads a link target as `href` writes it; nil for anything that is not an absolute `box://` path or that climbs with `.` or `..`.
    init?(href: String) {
        guard href.hasPrefix(Self.scheme + "/"), let decoded = String(href.dropFirst(Self.scheme.count)).removingPercentEncoding else { return nil }
        let segments = decoded.split(separator: "/", omittingEmptySubsequences: false).enumerated().filter { $0.offset == 0 || !$0.element.isEmpty }.map(\.element)
        guard !segments.contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        let joined = segments.joined(separator: "/")
        self.init(path: joined.isEmpty ? "/" : joined, folder: decoded.hasSuffix("/"))
    }

    /// The last segment of an absolute path.
    static func baseName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// What `encodeURIComponent` leaves alone, without the parentheses, which would end a Markdown link early.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'")

    private static func encode(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: unreserved) ?? segment
    }

    /// The folder uploads land in for the month `now` falls in, in `calendar`'s time: `<home>/Inbox/<yyyy-mm>`.
    static func inboxFolder(_ now: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: now)
        return home + "/Inbox/" + String(format: "%04d-%02d", parts.year!, parts.month!)
    }

    private static let line = try! NSRegularExpression(pattern: #"^\[(?:\\.|[^\]\\])*\]\((box:///[^)\s]*)\)$"#)

    /// The links a message opens with, one Markdown link to a file per line as the composer writes them, and the rest of
    /// the message after them.
    static func leading(in content: String) -> (links: [BoxLink], rest: String) {
        var links: [BoxLink] = []
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false)[...]
        while let first = lines.first {
            let text = String(first)
            guard let match = line.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let target = Range(match.range(at: 1), in: text),
                  let link = BoxLink(href: String(text[target]))
            else { break }
            links.append(link)
            lines = lines.dropFirst()
        }
        return (links, lines.joined(separator: "\n"))
    }
}
