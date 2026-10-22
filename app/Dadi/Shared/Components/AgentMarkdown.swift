import MarkdownView
import SwiftUI

/// Agent Markdown as dadi shows it, the same as thaali's Streamdown:
/// CommonMark with GitHub's tables, task lists, strikethrough and autolinks,
/// LaTeX math inline (`$…$`, `\(…\)`) and on its own line (`$$…$$`, `\[…\]`),
/// highlighted code, links, images, quotes and headings, in dadi's ink with
/// sage links and accents. Text stays selectable.
struct AgentMarkdown: View {
    let source: String

    var body: some View {
        MarkdownView(source)
            .markdownMathRenderingEnabled()
            .markdownFontGroup(AgentMarkdownFonts())
            .markdownLinksUnderlined()
            .tint(.sageDeep, for: .link)
            .tint(.sageDeep, for: .inlineCodeBlock)
            .tint(.sageDeep, for: .blockQuote)
            .markdownBlockQuoteStyle(SageQuoteStyle())
            .markdownTableStyle(RuledTableStyle())
            .markdownCodeBlockStyle(.default(lightTheme: "xcode", darkTheme: "atom-one-dark"))
            .backgroundStyle(.boneRaised)
            .foregroundStyle(.ink)
            .lineSpacing(3)
            .textSelection(.enabled)
    }
}

/// Inline Markdown alone (emphasis, code and links), for Ankur's own words in
/// his bubbles, which are plain text far more often than not.
enum InlineMarkdown {
    /// `text` with its inline Markdown, links and code in dadi's colors.
    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        var attributed: AttributedString
        do {
            attributed = try AttributedString(markdown: text, options: options)
        } catch {
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

/// The thread's type: body text at `.body`, as before, and headings sized for
/// a message rather than a page.
private struct AgentMarkdownFonts: MarkdownFontGroup {
    var h1: any CustomCTFontConvertible { Font.title3.weight(.semibold) }
    var h2: any CustomCTFontConvertible { Font.headline }
    var h3: any CustomCTFontConvertible { Font.headline }
    var h4: any CustomCTFontConvertible { Font.subheadline.weight(.semibold) }
    var h5: any CustomCTFontConvertible { Font.subheadline.weight(.semibold) }
    var h6: any CustomCTFontConvertible { Font.subheadline }
    var body: any CustomCTFontConvertible { Font.body }
    var codeBlock: any CustomCTFontConvertible { Font.callout.monospaced() }
    var blockQuote: any CustomCTFontConvertible { Font.body }
    var tableHeader: any CustomCTFontConvertible { Font.subheadline.weight(.semibold) }
    var tableBody: any CustomCTFontConvertible { Font.subheadline }
    var inlineMath: any CustomCTFontConvertible { Font.body }
    var displayMath: any CustomCTFontConvertible { Font.body }
}

/// A quote set in from a sage bar, in muted ink.
private struct SageQuoteStyle: MarkdownBlockQuoteStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .foregroundStyle(.inkMuted)
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Capsule().fill(.sageLine).frame(width: 3)
            }
    }
}

/// A table ruled in dadi's rule color, its header on raised bone; one too
/// wide for the screen scrolls sideways.
private struct RuledTableStyle: MarkdownTableStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            RuledTable(configuration: configuration)
            ScrollView(.horizontal) {
                RuledTable(configuration: configuration)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct RuledTable: View {
    let configuration: MarkdownTableStyleConfiguration

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            configuration.table.header
                .markdownTableRowBackgroundStyle(.boneRaised)
            ForEach(Array(configuration.table.rows.enumerated()), id: \.offset) { _, row in
                row
            }
        }
        .markdownTableCellOverlay {
            Rectangle().strokeBorder(.rule, lineWidth: 0.5)
        }
        .markdownTableCellPadding(.vertical, 6)
        .markdownTableCellPadding(.horizontal, 10)
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(.rule)
        }
    }
}
