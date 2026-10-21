import SwiftUI

/// One agent's thread: its history, live replies from Hath's events, and the
/// composer to reply as Ankur.
struct ThreadView: View {
    let hath: HathClient
    let agentId: String
    let name: String
    /// The newest event from Home's stream; messages for this agent are added.
    let live: HathEvent?

    @State private var messages: [DurableMessage] = []
    @State private var loadError: String?
    @State private var sendError: String?
    @State private var draft = ""
    @State private var sending = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let loadError {
                        Label(loadError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    ForEach(messages) { message in
                        bubble(message)
                    }
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            VStack(spacing: 6) {
                if let sendError {
                    Text(sendError).font(.callout).foregroundStyle(.red)
                }
                Composer(text: $draft, placeholder: "Message \(name)…", busy: sending, send: send)
            }
            .padding()
        }
        .navigationTitle(name)
        .task { await load() }
        .onChange(of: live) { _, event in
            guard case .message(let id, let message)? = event, id == agentId else { return }
            insert(message)
        }
    }

    @ViewBuilder
    private func bubble(_ message: DurableMessage) -> some View {
        if message.kind == .notice {
            Text(message.content)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        } else {
            HStack {
                if message.fromUser { Spacer(minLength: 48) }
                Text(LocalizedStringKey(message.content))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(message.fromUser ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.fill.quaternary), in: .rect(cornerRadius: 18))
                if !message.fromUser { Spacer(minLength: 48) }
            }
        }
    }

    private func load() async {
        do {
            messages = try await hath.messages(agentId: agentId)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Adds `message` in seq order unless it is already shown.
    private func insert(_ message: DurableMessage) {
        guard !messages.contains(where: { $0.seq == message.seq }) else { return }
        messages.append(message)
        messages.sort { $0.seq < $1.seq }
    }

    private func send() {
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !sending else { return }
        sending = true
        sendError = nil
        Task {
            defer { sending = false }
            do {
                let sent = try await hath.send(words, to: agentId)
                draft = ""
                insert(DurableMessage(seq: sent.seq, fromAgentId: nil, toAgentId: agentId, content: sent.content, attachments: sent.attachments, kind: .message, createdAt: sent.createdAt))
            } catch {
                sendError = error.localizedDescription
            }
        }
    }
}
