import Foundation

/// Which math a message holds, by thaali's rule (`src/shared/lib/content/math.ts`),
/// so prices stay prices: `$$…$$`, `\(…\)` and `\[…\]` are always math, while
/// a single-dollar `$…$` is math only when it reads as LaTeX. Its opening `$`
/// is not followed by whitespace, a digit or another `$`; its closing `$` is
/// on the same line and not preceded by whitespace; neither touches a word
/// character or another `$` outside; and it holds `\`, `^` or `_`. Any other
/// lone `$` is money. Code spans and fenced code are left as written.
enum MathDelimiters {
    /// How a math span was delimited.
    enum Delimiter: Equatable {
        case dollar, doubleDollar, parenthesis, bracket

        var open: String {
            switch self {
            case .dollar: "$"
            case .doubleDollar: "$$"
            case .parenthesis: "\\("
            case .bracket: "\\["
            }
        }

        var close: String {
            switch self {
            case .dollar: "$"
            case .doubleDollar: "$$"
            case .parenthesis: "\\)"
            case .bracket: "\\]"
            }
        }
    }

    /// One piece of a message.
    enum Piece: Equatable {
        /// Prose, code and escapes, as written.
        case text(String)
        /// TeX without its delimiters.
        case math(String, Delimiter)
        /// A `$` that is not math.
        case dollar
    }

    /// `source` for a renderer that reads every `$…$` as math: single-dollar
    /// math becomes `\(…\)` and every other lone `$` is escaped as `\$`.
    static func normalize(_ source: String) -> String {
        pieces(source).map { piece in
            switch piece {
            case .text(let text): text
            case .math(let tex, .dollar): "\\(" + tex + "\\)"
            case .math(let tex, let delimiter): delimiter.open + tex + delimiter.close
            case .dollar: "\\$"
            }
        }.joined()
    }

    /// `source` split into prose, math and money.
    static func pieces(_ source: String) -> [Piece] {
        let c = Array(source)
        var pieces: [Piece] = []
        var text = ""
        var fence: (marker: Character, count: Int)?
        var i = 0

        func emit(_ piece: Piece) {
            if !text.isEmpty { pieces.append(.text(text)); text = "" }
            pieces.append(piece)
        }

        while i < c.count {
            if i == 0 || c[i - 1] == "\n" {
                let end = c[i...].firstIndex(of: "\n").map { $0 + 1 } ?? c.count
                let marker = fenceMarker(c[i..<end])
                if let open = fence {
                    if let marker, marker.marker == open.marker, marker.count >= open.count { fence = nil }
                    text += String(c[i..<end])
                    i = end
                    continue
                }
                if let marker {
                    fence = marker
                    text += String(c[i..<end])
                    i = end
                    continue
                }
            }
            switch c[i] {
            case "\\":
                if i + 1 < c.count, c[i + 1] == "(" || c[i + 1] == "[" {
                    let delimiter: Delimiter = c[i + 1] == "(" ? .parenthesis : .bracket
                    if let close = find(Array(delimiter.close), in: c, from: i + 2) {
                        emit(.math(String(c[(i + 2)..<close]), delimiter))
                        i = close + 2
                        continue
                    }
                }
                let end = min(i + 2, c.count)
                text += String(c[i..<end])
                i = end
            case "`":
                let run = c[i...].prefix { $0 == "`" }.count
                if let close = closingRun(of: run, in: c, from: i + run) {
                    text += String(c[i..<(close + run)])
                    i = close + run
                } else {
                    text += String(c[i..<(i + run)])
                    i += run
                }
            case "$":
                if i + 1 < c.count, c[i + 1] == "$" {
                    if let close = find(["$", "$"], in: c, from: i + 2), close > i + 2 {
                        emit(.math(String(c[(i + 2)..<close]), .doubleDollar))
                        i = close + 2
                    } else {
                        emit(.dollar)
                        emit(.dollar)
                        i += 2
                    }
                } else if let close = singleDollarClose(in: c, opening: i) {
                    emit(.math(String(c[(i + 1)..<close]), .dollar))
                    i = close + 1
                } else {
                    emit(.dollar)
                    i += 1
                }
            default:
                text.append(c[i])
                i += 1
            }
        }
        if !text.isEmpty { pieces.append(.text(text)) }
        return pieces
    }

    /// Where the single-dollar math opening at `opening` closes, when it
    /// reads as LaTeX by the rule above.
    private static func singleDollarClose(in c: [Character], opening: Int) -> Int? {
        if opening > 0, isWord(c[opening - 1]) || c[opening - 1] == "$" { return nil }
        guard opening + 1 < c.count else { return nil }
        let first = c[opening + 1]
        guard !first.isWhitespace, !first.isNumber, first != "$" else { return nil }
        var close = opening + 1
        while close < c.count, c[close] != "$" || c[close - 1] == "\\" {
            if c[close].isNewline { return nil }
            close += 1
        }
        guard close < c.count, !c[close - 1].isWhitespace else { return nil }
        if close + 1 < c.count, isWord(c[close + 1]) || c[close + 1] == "$" { return nil }
        guard c[(opening + 1)..<close].contains(where: { $0 == "\\" || $0 == "^" || $0 == "_" }) else { return nil }
        return close
    }

    private static func isWord(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// The first index at or after `start` where `needle` begins.
    private static func find(_ needle: [Character], in c: [Character], from start: Int) -> Int? {
        guard start <= c.count - needle.count else { return nil }
        return (start...(c.count - needle.count)).first { Array(c[$0..<($0 + needle.count)]) == needle }
    }

    /// Where a run of exactly `count` backticks closes a code span.
    private static func closingRun(of count: Int, in c: [Character], from start: Int) -> Int? {
        var i = start
        while i < c.count {
            guard c[i] == "`" else { i += 1; continue }
            let run = c[i...].prefix { $0 == "`" }.count
            if run == count { return i }
            i += run
        }
        return nil
    }

    /// The fence a line opens or closes: up to three spaces, then three or
    /// more backticks or tildes.
    private static func fenceMarker(_ line: ArraySlice<Character>) -> (marker: Character, count: Int)? {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let rest = line.dropFirst(indent)
        guard let marker = rest.first, marker == "`" || marker == "~" else { return nil }
        let count = rest.prefix { $0 == marker }.count
        return count >= 3 ? (marker, count) : nil
    }
}
