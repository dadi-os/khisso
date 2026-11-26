import SwiftUI

/// The agent's charter as an expander row at the bottom of its sheet, with its size in tokens at the end.
struct CharterRow: View {
    let agent: AgentRecord

    /// Characters per token Hath measured for the model's text; a charter's size in tokens is its characters over this.
    private static let charsPerToken = 2.37

    @State private var open = false

    /// The charter's size as its row says it: "~1.2k tokens".
    static func size(_ charter: String) -> String {
        "~\(WakeFormat.compact(Int((Double(charter.count) / charsPerToken).rounded()))) tokens"
    }

    var body: some View {
        Expandable(isOpen: $open, icon: "doc.text") {
            Text("Charter")
        } trailing: {
            Text(Self.size(agent.systemPrompt))
        } content: {
            AgentMarkdown(source: agent.systemPrompt, compact: true)
        }
    }
}
