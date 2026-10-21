import SwiftUI

/// Agent text as dadi shows it: paragraphs, headings, bulleted and numbered
/// lists, quotes and fenced code blocks, with inline emphasis, code and links.
struct MarkdownText: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlock.parse(source).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(Self.inline(text))
                .font(.body)
                .foregroundStyle(.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(level == 1 ? .title3.weight(.semibold) : .headline)
                .foregroundStyle(.ink)
                .padding(.top, 4)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.sageText)
                            .frame(minWidth: 16, alignment: .trailing)
                        Text(Self.inline(item))
                            .font(.body)
                            .foregroundStyle(.ink)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .quote(let text):
            Text(Self.inline(text))
                .font(.body)
                .italic()
                .foregroundStyle(.inkMuted)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Capsule().fill(.sageLine).frame(width: 3) }
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(.callout.monospaced())
                    .foregroundStyle(.ink)
                    .padding(12)
            }
            .scrollIndicators(.hidden)
            .background(.sage.opacity(0.1), in: .rect(cornerRadius: 12))
        }
    }

    /// Inline markdown in `text`, styled with dadi's link and code colors.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        guard var attributed = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        for run in attributed.runs {
            if run.link != nil {
                attributed[run.range].foregroundColor = .sageDeep
                attributed[run.range].underlineStyle = .single
            }
            if run.inlinePresentationIntent?.contains(.code) == true {
                attributed[run.range].font = .callout.monospaced()
                attributed[run.range].backgroundColor = .sage.opacity(0.12)
            }
        }
        return attributed
    }
}

/// One block of a markdown message.
enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, String)
    case list(ordered: Bool, [String])
    case quote(String)
    case code(String)

    /// Splits `source` into blocks. Unknown syntax stays as paragraph text.
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var list: (ordered: Bool, items: [String])?
        var code: [String]?

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        func flushList() {
            if let current = list {
                blocks.append(.list(ordered: current.ordered, current.items))
                list = nil
            }
        }

        for raw in source.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let open = code {
                    blocks.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph()
                    flushList()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(raw)
                continue
            }
            if line.isEmpty {
                flushParagraph()
                flushList()
                continue
            }
            if let marker = line.firstIndex(of: " "), line[..<marker].allSatisfy({ $0 == "#" }), (1...6).contains(line.distance(from: line.startIndex, to: marker)) {
                flushParagraph()
                flushList()
                blocks.append(.heading(level: line.distance(from: line.startIndex, to: marker), String(line[line.index(after: marker)...])))
                continue
            }
            if let item = bullet(line) {
                flushParagraph()
                if list?.ordered != false { flushList(); list = (false, []) }
                list?.items.append(item)
                continue
            }
            if let item = numbered(line) {
                flushParagraph()
                if list?.ordered != true { flushList(); list = (true, []) }
                list?.items.append(item)
                continue
            }
            if line.hasPrefix("> ") {
                flushParagraph()
                flushList()
                blocks.append(.quote(String(line.dropFirst(2))))
                continue
            }
            flushList()
            paragraph.append(line)
        }
        if let open = code { blocks.append(.code(open.joined(separator: "\n"))) }
        flushParagraph()
        flushList()
        return blocks
    }

    private static func bullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func numbered(_ line: String) -> String? {
        guard let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }),
              !line[..<dot].isEmpty, line[..<dot].allSatisfy(\.isNumber),
              line[line.index(after: dot)...].hasPrefix(" ") else { return nil }
        return String(line[line.index(dot, offsetBy: 2)...])
    }
}
