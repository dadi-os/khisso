import SwiftUI

/// A titled row on the agent sheet that opens to its content, with a summary beside the title.
struct SheetDisclosure<Content: View>: View {
    let title: String
    /// What the section holds, said while it is closed.
    let summary: String
    @Binding var isOpen: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(Motion.settle) { isOpen.toggle() } } label: {
                HStack {
                    Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.ink)
                    Text(summary).font(.footnote).foregroundStyle(.inkMuted)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.inkFaint).rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if isOpen { content() }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ink.opacity(0.04), in: .rect(cornerRadius: 16, style: .continuous))
    }
}

/// What the agent is: its parent, when it was made and last active, its current step, the messages queued
/// to send, and its charter behind a disclosure.
struct AboutSection: View {
    let agent: AgentRecord
    let nameOf: (String) -> String
    /// Opens the parent's sheet.
    let selectAgent: (String) -> Void

    /// Characters per token Hath measured for the model's text; a charter's size in tokens is its characters over this.
    private static let charsPerToken = 2.37

    @State private var charterOpen = false

    private var pending: [AgentRecord.Running.Status.Pending] { agent.running.status?.pending ?? [] }

    /// The charter's size as its row says it: "~1.2k tokens · 2.8k chars".
    static func charterSummary(_ charter: String) -> String {
        "~\(WakeFormat.compact(Int((Double(charter.count) / charsPerToken).rounded()))) tokens · \(WakeFormat.compact(charter.count)) chars"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ABOUT").font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(.inkFaint)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("Parent").foregroundStyle(.inkFaint)
                    if let parent = agent.parentAgentId {
                        AgentLink(agentId: parent, name: nameOf(parent), select: selectAgent)
                    } else {
                        Text("None").foregroundStyle(.inkMuted)
                    }
                }
                GridRow {
                    Text("Created").foregroundStyle(.inkFaint)
                    Text(agent.createdAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()).foregroundStyle(.inkMuted)
                }
                GridRow {
                    Text("Last active").foregroundStyle(.inkFaint)
                    Text(agent.updatedAt, format: .relative(presentation: .named)).foregroundStyle(.inkMuted)
                }
                if let step = agent.running.status?.step {
                    GridRow {
                        Text("Step").foregroundStyle(.inkFaint)
                        Text(step).font(.system(.footnote, design: .monospaced)).foregroundStyle(.inkMuted).textSelection(.enabled)
                    }
                }
            }
            .font(.subheadline)
            if !pending.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Queued to send · \(pending.count)").font(.caption.weight(.semibold)).foregroundStyle(.inkMuted)
                    ForEach(pending, id: \.id) { message in
                        Text("To \(message.to.map(nameOf) ?? "Ankur")\(message.expectsReply ? " (expects a reply)" : ""): \(message.preview)")
                            .font(.footnote)
                            .foregroundStyle(.inkMuted)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 4)
            }
            SheetDisclosure(title: "Charter", summary: Self.charterSummary(agent.systemPrompt), isOpen: $charterOpen) {
                AgentMarkdown(source: agent.systemPrompt, compact: true).padding(.bottom, 12)
            }
        }
    }
}
