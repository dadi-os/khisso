import SwiftUI

/// The latest agent threads: a thinking agent shows thaali's flowing dots in
/// place of its last line, a working one says so. A thread opens on its
/// latest message with a dictated reply.
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
        HStack(spacing: 8) {
            Text(String(thread.name.prefix(1)))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Agent.hue(thread.agentId))
                .frame(width: 26, height: 26)
                .background(Agent.hue(thread.agentId).opacity(0.22), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(thread.name).font(.footnote.weight(.semibold)).lineLimit(1)
                if thread.thinking {
                    ThinkingMark().frame(height: 14)
                } else if thread.working {
                    Text("working").font(.caption2).foregroundStyle(.sage)
                } else {
                    Text((thread.fromUser ? "You: " : "") + Agent.preview(thread.lastMessage))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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

    private var message: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        do {
            return try AttributedString(markdown: (thread.fromUser ? "You: " : "") + thread.lastMessage, options: options)
        } catch {
            return AttributedString(thread.lastMessage)
        }
    }
}
