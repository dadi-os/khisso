import SwiftUI

/// One agent's thread: its history by day, live replies from Hath's events,
/// thaali's lane pill over the composer while the agent thinks or works, and
/// the composer to reply as Ankur. Agent text runs the full width on the field
/// as rendered markdown and scrolls up under the bars; Ankur's words are sage
/// bubbles.
struct ThreadView: View {
    let hath: HathClient
    let agentId: String
    let name: String
    /// The newest event from Home's stream; messages for this agent are added.
    let live: HathEvent?
    /// The agent's lanes running now.
    let lanes: Set<Lane>

    @State private var messages: [DurableMessage] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var sendError: String?
    @State private var draft = ""
    @State private var sending = false
    @State private var sent = 0
    @State private var received = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.danger)
                        .padding(.vertical, 20)
                }
                if loaded && messages.isEmpty && loadError == nil {
                    empty
                }
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    let previous = index > 0 ? messages[index - 1] : nil
                    if previous.map({ !Calendar.current.isDate($0.createdAt, inSameDayAs: message.createdAt) }) ?? true {
                        DayMark(date: message.createdAt)
                    }
                    row(message, opensGroup: previous.map { $0.fromUser != message.fromUser || $0.kind == .notice } ?? true)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: message.fromUser ? .bottomTrailing : .bottomLeading)), removal: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .animation(Motion.settle, value: messages)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectHidden(true, for: .bottom)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                LaneChip(lanes: lanes)
                if let sendError {
                    Label(sendError, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.danger)
                        .transition(.opacity)
                }
                Composer(text: $draft, placeholder: "Message \(name)…", busy: sending, lanes: lanes, send: send)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .navigationTitle(name)
        .sensoryFeedback(.impact(weight: .light), trigger: sent)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: received)
        .task { await load() }
        .onChange(of: live) { _, event in
            guard case .message(let id, let message)? = event, id == agentId else { return }
            if insert(message), !message.fromUser { received += 1 }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text(String(name.prefix(1)))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(Agent.hue(agentId))
                .frame(width: 64, height: 64)
                .background(Agent.hue(agentId).opacity(0.14), in: .circle)
            Text(name).font(.headline).foregroundStyle(.ink)
            Text("No messages yet. Say something to get it started.")
                .font(.callout)
                .foregroundStyle(.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    @ViewBuilder
    private func row(_ message: DurableMessage, opensGroup: Bool) -> some View {
        if message.kind == .notice {
            Text(message.content)
                .font(.footnote)
                .foregroundStyle(.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.sage.opacity(0.08), in: .capsule)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        } else if message.fromUser {
            VStack(alignment: .trailing, spacing: 6) {
                if !message.content.isEmpty {
                    Text(MarkdownText.inline(message.content))
                        .font(.body)
                        .foregroundStyle(.bone)
                        .textSelection(.enabled)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .background(.sageDeep, in: .rect(cornerRadius: 20, style: .continuous))
                }
                attachments(message.attachments)
                time(message)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 56)
            .padding(.top, opensGroup ? 22 : 12)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if opensGroup {
                    HStack(spacing: 8) {
                        Text(String(name.prefix(1)))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Agent.hue(agentId))
                            .frame(width: 24, height: 24)
                            .background(Agent.hue(agentId).opacity(0.16), in: .circle)
                        Text(name).font(.footnote.weight(.semibold)).foregroundStyle(.inkMuted)
                    }
                }
                MarkdownText(source: message.content)
                attachments(message.attachments)
                time(message)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, opensGroup ? 24 : 16)
        }
    }

    /// A message's time under it, as thaali marks each message, so one message
    /// is easy to tell from the next.
    private func time(_ message: DurableMessage) -> some View {
        Text(message.createdAt, format: .dateTime.hour().minute())
            .font(.caption2)
            .foregroundStyle(.inkFaint)
    }

    @ViewBuilder
    private func attachments(_ files: [AttachmentSummary]) -> some View {
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(files) { file in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.filename).font(.footnote.weight(.medium)).foregroundStyle(.ink).lineLimit(1)
                            Text(file.description ?? ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
                                .font(.caption2)
                                .foregroundStyle(.inkMuted)
                                .lineLimit(2)
                        }
                    } icon: {
                        Image(systemName: file.mediaType.hasPrefix("image/") ? "photo" : "doc")
                            .foregroundStyle(.sageDeep)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.boneRaised, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.rule))
                }
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
        loaded = true
    }

    /// Adds `message` in seq order unless it is already shown; true when added.
    @discardableResult
    private func insert(_ message: DurableMessage) -> Bool {
        guard !messages.contains(where: { $0.seq == message.seq }) else { return false }
        messages.append(message)
        messages.sort { $0.seq < $1.seq }
        return true
    }

    private func send() {
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !sending else { return }
        sending = true
        sendError = nil
        Task {
            defer { sending = false }
            do {
                let reply = try await hath.send(words, to: agentId)
                draft = ""
                sent += 1
                insert(DurableMessage(seq: reply.seq, fromAgentId: nil, toAgentId: agentId, content: reply.content, attachments: reply.attachments, kind: .message, createdAt: reply.createdAt))
            } catch {
                withAnimation(Motion.snap) { sendError = error.localizedDescription }
            }
        }
    }
}

/// A day's heading in a thread: Today, Yesterday, or the date.
private struct DayMark: View {
    let date: Date

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
            .padding(.bottom, 4)
    }

    private var label: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
