import SwiftUI

/// An agent's name wherever the sheet shows one: a button that opens that agent's sheet. Ankur has no
/// sheet, so his name (`agentId` nil) is plain text.
struct AgentLink: View {
    /// The agent it opens; nil is Ankur.
    let agentId: String?
    let name: String
    /// Selects the agent, replacing the sheet's content.
    let select: (String) -> Void

    var body: some View {
        if let agentId {
            Button { select(agentId) } label: {
                Text(name).fontWeight(.semibold).foregroundStyle(.sageDeep)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows \(name)")
        } else {
            Text(name)
        }
    }
}
