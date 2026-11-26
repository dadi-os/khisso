import SwiftUI

/// The latest agent threads: a working or waiting agent says so in place of its last line, and one parked on
/// Ankur's answer or blocked says that. A thread opens on its latest message with a dictated reply.
struct AgentsPage: View {
    let store: WatchStore

    var body: some View {
        NavigationStack {
            List(store.snapshot?.threads ?? []) { thread in
                NavigationLink(value: thread) {
                    Row(thread: thread)
                }
            }
            .overlay {
                if store.snapshot == nil {
                    Text("Open dadi on your iPhone to bring your agents here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .navigationTitle("Agents")
            .navigationDestination(for: WatchSnapshot.Thread.self) { thread in
                ThreadPage(store: store, thread: thread)
            }
        }
    }
}

private struct Row: View {
    let thread: WatchSnapshot.Thread

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                if thread.state != .idle {
                    StateDot(state: thread.state, mark: nil)
                }
                Text(thread.name).font(.footnote.weight(thread.unread > 0 ? .bold : .semibold)).lineLimit(1)
                if thread.unread > 0 {
                    Spacer(minLength: 2)
                    Text("\(thread.unread)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .background(.sage, in: .capsule)
                }
            }
            if let attention = thread.attention {
                Text(attention == .blocked ? "Blocked" : "Needs your input")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(attention == .blocked ? Color.lateInk : .tide)
            } else if thread.state != .idle {
                Text(thread.state == .working ? "working" : "waiting").font(.caption2).foregroundStyle(thread.state == .working ? Color.sage : .tide)
            } else {
                Text((thread.fromUser ? "You: " : "") + Agent.preview(thread.lastMessage))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// One thread on the wrist: the latest message and a dictated reply.
private struct ThreadPage: View {
    let store: WatchStore
    let thread: WatchSnapshot.Thread

    @State private var outcome: String?
    @State private var sending = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let attention = thread.attention {
                    Text(attention == .blocked ? "\(thread.name) is blocked" : "\(thread.name) needs your input")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(attention == .blocked ? Color.lateInk : .tide)
                } else if thread.state != .idle {
                    Text(thread.state.label).font(.caption.weight(.semibold)).foregroundStyle(thread.state == .working ? Color.sage : .tide)
                }
                Text(thread.lastAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(thread.fromUser ? .secondary : .primary)
                TextFieldLink(prompt: Text("Reply to \(thread.name)")) {
                    Label(sending ? "Sending…" : "Reply", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                } onSubmit: { words in
                    sending = true
                    store.reply(words, to: thread.agentId) { error in
                        sending = false
                        outcome = error ?? "Sent"
                    }
                }
                .tint(.sageDeep)
                .disabled(sending)
                if let outcome {
                    Text(outcome).font(.caption2).foregroundStyle(outcome == "Sent" ? .sage : .danger)
                }
            }
        }
        .navigationTitle(thread.name)
    }

    /// The latest message with its inline markdown, and its math read as
    /// Unicode since the watch cannot typeset it.
    private var message: AttributedString {
        let text = UnicodeMath.text(thread.lastMessage)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        do {
            return try AttributedString(markdown: (thread.fromUser ? "You: " : "") + text, options: options)
        } catch {
            return AttributedString(text)
        }
    }
}
