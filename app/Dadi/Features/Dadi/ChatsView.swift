import SwiftUI

/// Chats: every conversation as a glass card under the day of its last
/// message (Today, Yesterday, then the date), as thaali's sidebar lists them,
/// under a search field. A row has the agent's name, when it last spoke, its
/// last words and its unread count, and opens with a dot while a lane
/// of the agent runs. Talking to Dadi is the dock, not this page.
struct ChatsView: View {
    let threads: [ThreadSummary]
    /// Each agent's running lanes.
    let lanes: (String) -> Set<Lane>
    /// Why the threads could not be read, if they could not.
    let error: String?
    /// True until the first answer.
    let loading: Bool
    /// Reads the threads again.
    let retry: () -> Void
    /// Opens an agent's thread.
    let open: (String) -> Void
    /// Opens an agent's sheet.
    let details: (String) -> Void

    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                search
                if let error {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.danger)
                        Button("Try again", action: retry).buttonStyle(.glass)
                    }
                    .padding(.horizontal, 4)
                } else if loading {
                    SkeletonRows(count: 6, height: 62)
                } else if threads.isEmpty {
                    EmptyState(title: "No chats yet", detail: "Tell Dadi what you need. It lands with the agent who owns it, and that chat opens.")
                        .padding(.top, 96)
                } else if days.isEmpty {
                    Text("No chat matches \u{201C}\(query)\u{201D}.")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 8)
                } else {
                    ForEach(days) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(day.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.inkMuted)
                                .padding(.horizontal, 6)
                                .padding(.top, 6)
                            GlassEffectContainer(spacing: 8) {
                                VStack(spacing: 8) { ForEach(day.threads) { card($0) } }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 140)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(Motion.settle, value: days.map(\.id))
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.subheadline.weight(.semibold)).foregroundStyle(.inkFaint)
            TextField("Search chats", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.inkFaint) }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private var days: [ChatGroups.Day] {
        ChatGroups.days(threads, matching: query)
    }

    private func card(_ thread: ThreadSummary) -> some View {
        let working = ChatGroups.isWorking(lanes(thread.agentId))
        return Button { open(thread.agentId) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    if working {
                        WorkingDot()
                    }
                    Text(thread.agentName)
                        .font(.subheadline.weight(thread.unread > 0 ? .bold : .semibold))
                        .foregroundStyle(.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(ChatGroups.when(thread.lastAt))
                        .font(.caption2)
                        .foregroundStyle(thread.unread > 0 ? Color.sageText : .inkFaint)
                }
                HStack(alignment: .top, spacing: 8) {
                    Text((thread.fromUser ? "You: " : "") + Agent.preview(thread.lastMessage))
                        .font(.footnote)
                        .foregroundStyle(thread.unread > 0 ? Color.ink : .inkMuted)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if thread.unread > 0 {
                        UnreadBadge(count: thread.unread)
                    }
                }
            }
            .animation(Motion.settle, value: working)
            .animation(Motion.pop, value: thread.unread)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { open(thread.agentId) } label: { Label("Open thread", systemImage: "bubble.left.and.text.bubble.right") }
            Button { details(thread.agentId) } label: { Label("Agent details", systemImage: "info.circle") }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
