import Foundation

/// A message split by the reply encoding thaali and khisso share: `box://` link lines, then the quoted message as
/// `> ` lines, one blank line, then the reply. `QuoteCard.blockquote` writes it.
struct ReplyQuote: Equatable {
    /// The link lines ahead of the quote, joined by newlines; empty when there are none or the message has no quote.
    let links: String
    /// The quoted words with each line's `> ` taken off; nil when the message quotes nothing.
    let quote: String?
    /// What follows the quote, or the whole message when it has none.
    let reply: String

    private static var linkLine: Regex<Substring> { /^!?\[(?:\\.|[^\]\\])*\]\(box:\/\/[^)\s]*\)$/ }

    /// Splits `content`. The quote is the run of `>` lines straight after the link lines and any blank lines, and must
    /// end at a blank line or the end of the text; a blockquote inside the reply is left alone.
    init(_ content: String) {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count, lines[index].wholeMatch(of: Self.linkLine) != nil { index += 1 }
        let linkEnd = index
        while index < lines.count, lines[index].isEmpty { index += 1 }
        let quoteStart = index
        while index < lines.count, lines[index].hasPrefix(">") { index += 1 }
        guard index > quoteStart, index == lines.count || lines[index].isEmpty else {
            links = ""
            quote = nil
            reply = content
            return
        }
        links = lines[..<linkEnd].joined(separator: "\n")
        quote = lines[quoteStart..<index].map { $0.hasPrefix("> ") ? String($0.dropFirst(2)) : String($0.dropFirst(1)) }.joined(separator: "\n")
        reply = index < lines.count ? lines[(index + 1)...].joined(separator: "\n") : ""
    }

    /// The message's text without its quote: the links, then the reply.
    var body: String {
        links.isEmpty ? reply : reply.isEmpty ? links : links + "\n" + reply
    }
}
