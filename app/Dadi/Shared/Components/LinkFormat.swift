import Foundation

/// How links in messages are worded, as thaali's ChatLink: no chip, the link's own words, and for a bare URL its host
/// and the start of its path. A target that is not an absolute http(s) URL is plain text.
enum LinkFormat {
    /// The longest a bare URL's host-and-path label is before it is cut with an ellipsis.
    static let labelMax = 36

    /// The absolute http(s) URL `href` names, or nil for anything else (relative, mailto:, javascript:, unparseable).
    static func parseHTTP(_ href: String) -> URL? {
        guard let url = URL(string: href), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host() != nil else { return nil }
        return url
    }

    /// The host without a leading www.
    static func host(_ url: URL) -> String {
        let host = url.host() ?? ""
        return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// What a link with no words of its own shows: the host and the start of its path, cut at `labelMax`.
    static func bareLabel(_ url: URL) -> String {
        var path = url.path()
        if path.hasSuffix("/") { path.removeLast() }
        let label = host(url) + path
        return label.count > labelMax ? String(label.prefix(labelMax - 1)) + "…" : label
    }

    /// Whether `text` is just the URL spelled out, with or without its scheme, www or trailing slash.
    static func isBare(_ text: String, url: URL) -> Bool {
        func spelled(_ value: String) -> String {
            var out = value.trimmingCharacters(in: .whitespaces)
            for prefix in ["https://", "http://", "www."] where out.lowercased().hasPrefix(prefix) { out.removeFirst(prefix.count) }
            if out.hasSuffix("/") { out.removeLast() }
            return out
        }
        let whole = spelled(url.absoluteString)
        let noFragment = spelled(url.absoluteString.split(separator: "#", maxSplits: 1).first.map(String.init) ?? "")
        return spelled(text) == whole || spelled(text) == noFragment
    }

    /// The words a link shows: its own text, or `bareLabel` when its text is only the URL or empty.
    static func label(_ text: String, url: URL) -> String {
        text.trimmingCharacters(in: .whitespaces).isEmpty || isBare(text, url: url) ? bareLabel(url) : text
    }

    private static let pattern = try! NSRegularExpression(pattern: #"\[([^\]\n]*)\]\(((?:[^()\s]|\([^()\s]*\))+)\)|<(https?://[^>\s]+)>|(https?://[^\s<>()\[\]`]+)"#)

    /// `markdown` with every link in the form the renderer draws: a bare URL becomes a link labelled by its host and
    /// path, a link whose text is only its URL takes that label, and a link to anything but http(s) or the box is its text.
    /// Fenced code and inline code are left as written.
    static func normalize(_ markdown: String) -> String {
        var fenced = false
        return markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                fenced.toggle()
                return String(line)
            }
            guard !fenced else { return String(line) }
            return line.split(separator: "`", omittingEmptySubsequences: false).enumerated().map { index, part in
                index % 2 == 1 ? String(part) : rewrite(String(part))
            }
            .joined(separator: "`")
        }
        .joined(separator: "\n")
    }

    private static func rewrite(_ text: String) -> String {
        let source = text as NSString
        var out = ""
        var cursor = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            out += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = match.range.location + match.range.length
            func group(_ index: Int) -> String? {
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : source.substring(with: range)
            }
            if let destination = group(2) {
                let words = group(1) ?? ""
                if let url = parseHTTP(destination) {
                    out += "[\(label(words, url: url))](\(destination))"
                } else if BoxLink(href: destination) != nil {
                    out += source.substring(with: match.range)
                } else {
                    out += words
                }
                continue
            }
            let raw = group(3) ?? group(4) ?? ""
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?'\""))
            let tail = String(raw.dropFirst(trimmed.count))
            if let url = parseHTTP(trimmed) { out += "[\(bareLabel(url))](\(trimmed))\(tail)" } else { out += raw }
        }
        return out + source.substring(from: cursor)
    }
}
