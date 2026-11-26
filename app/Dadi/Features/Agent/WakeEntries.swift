import SwiftUI

/// The entries of an open wake, oldest to newest: messages as bubbles aligned by direction, model turns
/// as quiet blocks, and Hath's own notes to the agent as dashed bubbles.
struct WakeEntryList: View {
    let hath: HathClient
    /// The agent whose wake it is; a truncated result is fetched under its id.
    let agentId: String
    /// The entries to draw, oldest first.
    let entries: [WakeEntry]
    let nameOf: (String) -> String
    /// Opens the sheet of the agent a message's counterpart names.
    let selectAgent: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(WakeFormat.inMinutes(entries)) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.clock).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.inkFaint)
                    ForEach(group.entries) { entry in
                        switch entry {
                        case .message(let message): MessageBubble(entry: message, nameOf: nameOf, selectAgent: selectAgent)
                        case .turn(let turn): TurnBlock(hath: hath, agentId: agentId, turn: turn)
                        }
                    }
                }
            }
        }
    }
}

/// What a message's status says it leaves open, as a tag.
enum StatusTag {
    /// "Needs input" or "Blocked"; nil for `done` and no status.
    static func text(_ status: MessageStatus?) -> String? {
        switch status {
        case .needsInput: "Needs input"
        case .blocked: "Blocked"
        case .done, nil: nil
        }
    }
}

/// One message of the wake: received at the left, sent at the right, under its counterpart's name and the time.
private struct MessageBubble: View {
    let entry: WakeMessageEntry
    let nameOf: (String) -> String
    let selectAgent: (String) -> Void

    /// Characters past which a message folds until opened.
    private static let folded = 280

    @State private var open = false

    private var received: Bool { entry.direction == .received }

    /// Hath's own note to the agent, not something anyone wrote.
    private var note: Bool { entry.message.kind == .notice }

    private var counterpartId: String? { received ? entry.message.fromAgentId : entry.message.toAgentId }

    var body: some View {
        VStack(alignment: received ? .leading : .trailing, spacing: 4) {
            HStack(spacing: 0) {
                if note {
                    Text("Note from hath")
                } else {
                    Text(received ? "From " : "To ")
                    AgentLink(agentId: counterpartId, name: counterpartId.map(nameOf) ?? "Ankur", select: selectAgent)
                }
                if let tag = StatusTag.text(entry.message.status) {
                    Text(" · ")
                    Text(tag.lowercased()).fontWeight(.medium).foregroundStyle(entry.message.status == .blocked ? Color.lateInk : .tideText)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.inkMuted)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(.ink)
                    .lineLimit(open ? nil : 5)
                    .textSelection(.enabled)
                if entry.message.content.count > Self.folded {
                    Button(open ? "Show less" : "Show more") { withAnimation(Motion.settle) { open.toggle() } }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.sageDeep)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(note ? .clear : received ? Color.sage.opacity(0.12) : Color.ink.opacity(0.04), in: .rect(cornerRadius: 14, style: .continuous))
            .overlay {
                if note {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.sageLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                } else if !received {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.rule, lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: received ? .leading : .trailing)
        .accessibilityElement(children: .contain)
    }
}

/// One model turn: what it said, its thinking in a compact expandable row, and a row per tool call.
private struct TurnBlock: View {
    let hath: HathClient
    let agentId: String
    let turn: WakeTurn

    @State private var thinkingOpen = false

    private var firstLine: String {
        turn.thinking?.split(whereSeparator: \.isNewline).first { !$0.allSatisfy(\.isWhitespace) }.map(String.init) ?? ""
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(.rule).frame(width: 1)
            VStack(alignment: .leading, spacing: 6) {
                if let text = turn.text {
                    AgentMarkdown(source: text, compact: true)
                }
                if let thinking = turn.thinking {
                    Expandable(isOpen: $thinkingOpen, look: .row) {
                        Text("Thinking").fontWeight(.semibold)
                    } secondary: {
                        if !thinkingOpen { Text(firstLine).italic().lineLimit(1) }
                    } trailing: {
                        EmptyView()
                    } content: {
                        Text(thinking).font(.system(size: 12)).foregroundStyle(.inkMuted).textSelection(.enabled)
                    }
                }
                ForEach(turn.calls) { call in
                    CallRow(hath: hath, agentId: agentId, call: call)
                }
            }
        }
    }
}

/// One tool call as a line (state dot, name, target, a cut-short mark) that opens to its input and result.
private struct CallRow: View {
    let hath: HathClient
    let agentId: String
    let call: WakeToolCall

    /// Where the full result stands once asked for.
    private enum Full {
        case idle, loading
        case loaded(String)
        case failed(String)
    }

    @State private var open = false
    @State private var full = Full.idle

    var body: some View {
        Expandable(isOpen: $open, look: .row) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(call.name).font(.system(size: 12, design: .monospaced)).foregroundStyle(call.result?.isError == true ? Color.lateInk : .ink).lineLimit(1).fixedSize()
                Text(WakeFormat.target(call.input)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.inkMuted).lineLimit(1)
            }
        } trailing: {
            if call.result == nil {
                Text("running").foregroundStyle(.sageText)
            } else if call.result?.isError == true {
                Text("error").foregroundStyle(.lateInk)
            } else if call.result?.truncated == true {
                Text("cut short").foregroundStyle(.inkFaint)
            }
        } content: {
            details
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            block("INPUT", text: WakeFormat.pretty(call.input))
            if let result = call.result {
                block(result.truncated ? "RESULT (FIRST \(result.content.count) OF \(result.chars) CHARACTERS)" : "RESULT", text: WakeFormat.pretty(text: result.content), failed: result.isError)
                if result.truncated, let logId = call.logId, case .idle = full {
                    Button("Show full result") { Task { await load(logId) } }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.sageDeep)
                }
            }
            switch full {
            case .idle: EmptyView()
            case .loading: ProgressView().controlSize(.small)
            case .loaded(let text): block("FULL RESULT", text: text)
            case .failed(let message): Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.danger)
            }
        }
    }

    private func block(_ title: String, text: String, failed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.inkFaint)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(failed ? Color.lateInk : .ink)
                .textSelection(.enabled)
        }
    }

    private func load(_ logId: String) async {
        full = .loading
        do {
            full = .loaded(WakeFormat.pretty(text: WakeFormat.rawContent(try await hath.log(agentId: agentId, logId: logId))))
        } catch is CancellationError {
            full = .idle
        } catch {
            full = .failed(error.localizedDescription)
        }
    }
}
