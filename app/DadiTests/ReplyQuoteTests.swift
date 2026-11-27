import Foundation
import Testing
@testable import Khisso

/// The reply encoding thaali and khisso share: links, a `> ` quote, one blank line, the reply.
struct ReplyQuoteTests {
    private let link = "[a.png](box://Inbox/2026-11/a.png)"

    @Test func roundTripsWhatTheComposerWrites() {
        let written = QuoteCard.blockquote(plainText("**Bold** line one\nline two")) + "my reply\nsecond line"
        let parts = ReplyQuote(written)
        #expect(parts.quote == "Bold line one\nline two")
        #expect(parts.reply == "my reply\nsecond line")
        #expect(parts.links == "")
    }

    @Test func splitsLinksQuoteAndReply() {
        let parts = ReplyQuote(Inbox.message(paths: ["Inbox/2026-11/a.png"], typed: "> quoted\n\nanswer"))
        #expect(parts.links.hasPrefix("!") || parts.links.hasPrefix("["))
        #expect(parts.quote == "quoted")
        #expect(parts.reply == "answer")
        #expect(parts.body == parts.links + "\nanswer")
    }

    @Test func acceptsBlankLinesBetweenLinksAndQuote() {
        let parts = ReplyQuote("\(link)\n\n\n> q\n\nr")
        #expect(parts.links == link)
        #expect(parts.quote == "q")
        #expect(parts.reply == "r")
    }

    @Test func linksOnlyHaveNoQuote() {
        let text = "\(link)\n\(link)"
        let parts = ReplyQuote(text)
        #expect(parts.quote == nil)
        #expect(parts.reply == text)
    }

    @Test func linksAndReplyWithoutQuoteStayWhole() {
        let text = "\(link)\njust words"
        #expect(ReplyQuote(text).quote == nil)
        #expect(ReplyQuote(text).reply == text)
    }

    @Test func quoteOnlyHasAnEmptyReply() {
        let parts = ReplyQuote("> only a quote")
        #expect(parts.quote == "only a quote")
        #expect(parts.reply == "")
    }

    @Test func keepsBlankLinesInsideTheQuoteAndNestedBlockquotesInTheReply() {
        let parts = ReplyQuote("> one\n> \n> two\n\nanswer\n> not a quote\nend")
        #expect(parts.quote == "one\n\ntwo")
        #expect(parts.reply == "answer\n> not a quote\nend")
        #expect(ReplyQuote("> > nested\n\nr").quote == "> nested")
    }

    @Test func aQuoteMustEndAtABlankLine() {
        let text = "> q\nno blank line"
        #expect(ReplyQuote(text).quote == nil)
        #expect(ReplyQuote(text).reply == text)
    }

    @Test func aLongQuoteKeepsItsEllipsis() {
        let long = String(repeating: "word ", count: 80)
        let parts = ReplyQuote(QuoteCard.blockquote(long) + "reply")
        #expect(parts.quote?.hasSuffix("\u{2026}") == true)
        #expect(parts.quote?.count == 281)
        #expect(parts.reply == "reply")
    }
}
