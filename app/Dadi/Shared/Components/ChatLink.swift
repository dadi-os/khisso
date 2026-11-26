import MarkdownView
import SwiftUI

extension View {
    /// Draws the links of the Markdown below as dadi's links: inline blue text, no underline, no chip. Holding one shows
    /// the system's link preview with the full URL; bare URLs are worded by `LinkFormat` before they reach the renderer.
    func chatLinks() -> some View {
        self
            .markdownLinksUnderlined(false)
            .tint(.linkInk, for: .link)
    }
}
