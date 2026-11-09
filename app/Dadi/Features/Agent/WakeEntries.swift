import SwiftUI

/// The entries of an open wake, oldest to newest: messages as bubbles aligned by direction, model turns
/// as quiet blocks tagged by lane.
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
            ForEach(entries) { entry in
                switch entry {
                case .message(let message): MessageBubble(entry: message, nameOf: nameOf, selectAgent: selectAgent)
                case .turn(let turn): TurnBlock(hath: hath, agentId: agentId, turn: turn)
                }
            }
        }
    }
}

/// The time of day an entry happened.
private func clock(_ date: Date) -> Text {
    Text(date, format: .dateTime.hour().minute())
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

    private var counterpartId: String? { received ? entry.message.fromAgentId : entry.message.toAgentId }

    var body: some View {
        VStack(alignment: received ? .leading : .trailing, spacing: 4) {
            HStack(spacing: 0) {
                Text(received ? "From " : "To ")
                AgentLink(agentId: counterpartId, name: counterpartId.map(nameOf) ?? "Ankur", select: selectAgent)
                Text(" · ")
                clock(entry.at)
            }
            .font(.caption2)
            .foregroundStyle(.inkMuted)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.message.content)
                    .font(.footnote)
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
            .background(received ? Color.sage.opacity(0.12) : Color.ink.opacity(0.04), in: .rect(cornerRadius: 14, style: .continuous))
            .overlay { if !received { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.rule, lineWidth: 1) } }
        }
        .frame(maxWidth: .infinity, alignment: received ? .leading : .trailing)
        .accessibilityElement(children: .contain)
    }
}

/// One model turn: its lane and time, what it said, its thinking folded, and a line per tool call.
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
                HStack(spacing: 8) {
                    Text(turn.lane == .work ? "WORK" : "PROCESS").font(.caption2.weight(.semibold)).tracking(1)
                    clock(turn.at)
                }
                .font(.caption2)
                .foregroundStyle(.inkMuted)
                if let text = turn.text {
                    AgentMarkdown(source: text, compact: true)
                }
                if let thinking = turn.thinking {
                    VStack(alignment: .leading, spacing: 4) {
                        Button { thinkingOpen.toggle() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).rotationEffect(.degrees(thinkingOpen ? 90 : 0))
                                Text("Thinking").fontWeight(.semibold)
                                if !thinkingOpen { Text(firstLine).italic().lineLimit(1) }
                                Spacer(minLength: 0)
                            }
                            .font(.caption)
                            .foregroundStyle(.inkMuted)
                            .frame(minHeight: 32)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if thinkingOpen {
                            Text(thinking).font(.caption).foregroundStyle(.inkMuted).textSelection(.enabled).transition(.reveal)
                        }
                    }
                    .reveals(on: thinkingOpen)
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

    private var dot: Color {
        guard let result = call.result else { return .sage }
        return result.isError ? .danger : .sage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { open.toggle() } label: { line }
                .buttonStyle(.plain)
            if open { details.transition(.reveal) }
        }
        .reveals(on: open)
    }

    private var line: some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 6, height: 6).opacity(call.result == nil ? 0.5 : 1)
            Text(call.name).font(.system(.caption, design: .monospaced)).foregroundStyle(call.result?.isError == true ? Color.danger : .ink)
            Text(WakeFormat.target(call.input)).font(.system(.caption2, design: .monospaced)).foregroundStyle(.inkMuted).lineLimit(1)
            Spacer(minLength: 4)
            if call.result == nil { Text("running").font(.caption2).foregroundStyle(.sageText) }
            if call.result?.isError == true { Text("error").font(.caption2).foregroundStyle(.danger) }
            if call.result?.truncated == true {
                Text("cut")
                    .font(.caption2)
                    .foregroundStyle(.inkMuted)
                    .padding(.horizontal, 6)
                    .overlay { Capsule().strokeBorder(Color.sageLine, style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
            }
        }
        .frame(minHeight: 32)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(open ? "Hides the call's input and result" : "Shows the call's input and result")
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
        .padding(.leading, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .leading) { Rectangle().fill(.rule).frame(width: 1) }
        .padding(.leading, 6)
    }

    private func block(_ title: String, text: String, failed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.inkFaint)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(failed ? Color.danger : .ink)
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
