import SwiftUI

/// How agents read in lists: their ids made into names, a stable color each,
/// and a message as one plain line.
enum Agent {
    /// "finance-specialist" as "Finance specialist".
    static func displayName(_ id: String) -> String {
        let words = id.split(separator: "-").joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// The agent's color, the same every time: sage, clay or tide.
    static func hue(_ id: String) -> Color {
        let palette: [Color] = [.sageDeep, .clay, .tide]
        let sum = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }

    /// A message's first line without markdown, for previews.
    static func preview(_ content: String) -> String {
        let line = content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: line, options: options) else { return line }
        return String(parsed.characters)
    }
}
