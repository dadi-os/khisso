import Foundation

/// How agents read in lists: a message as one plain line. Agents are named
/// as Hath names them, as in thaali.
enum Agent {
    /// A message's first line without markdown, its math read as Unicode,
    /// for previews.
    static func preview(_ content: String) -> String {
        let line = UnicodeMath.text(content)
            .split(whereSeparator: \.isNewline)
            .first { !$0.allSatisfy(\.isWhitespace) }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        do {
            return String(try AttributedString(markdown: line, options: options).characters)
        } catch {
            return line
        }
    }
}
