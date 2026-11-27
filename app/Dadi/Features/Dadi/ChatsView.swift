import SwiftUI

/// Chats: every conversation as a glass card under the day of its last
/// message (Today, Yesterday, then the date), as thaali's sidebar lists them,
/// under a search field. A row has the agent's name, when it last spoke, its
/// last words and its unread count, and opens with the agent's state dot. Talking to Dadi is the dock, not this page.
struct ChatsView: View {
    let threads: [ThreadSummary]
    /// What the drawer narrowed the list to.
    @Binding var filter: ChatGroups.Filter
    /// What each agent is doing.
    let running: (String) -> AgentRecord.Running
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
                if filter != .all {
                    Button { filter = .all } label: {
                        Label("Showing \(filter.rawValue.lowercased()) chats. Show all", systemImage: "line.3.horizontal.decrease")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.sageText)
                            .padding(.horizontal, 6)
                            .frame(minHeight: 32)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
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
                    Text(query.isEmpty ? "No chat is \(filter.rawValue.lowercased())." : "No chat matches \u{201C}\(query)\u{201D}.")
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
            .padding(.top, 4)
            .padding(.bottom, 16)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectHidden(true, for: .all)
        .scrollEdge(.top, size: ScrollEdge.listTop)
        .scrollEdge(.bottom, size: ScrollEdge.listBottom)
        .safeAreaInset(edge: .top, spacing: 0) {
            search
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
        }
        .animation(Motion.settle, value: days.map(\.id))
        .animation(Motion.snap, value: filter)
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
        .frame(minHeight: 52)
        .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        .padding(.leading, 60)
    }

    private var days: [ChatGroups.Day] {
        ChatGroups.days(threads.filter { filter.keeps($0, state: running($0.agentId).state) }, matching: query)
    }

    private func card(_ thread: ThreadSummary) -> some View {
        let state = running(thread.agentId)
        return Button { open(thread.agentId) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    if state.state != .idle || state.mark(at: .now) != nil {
                        StateDot(state: state.state, mark: state.mark(at: .now))
                    }
                    Text(thread.agentName)
                        .font(.subheadline.weight(thread.unread > 0 ? .bold : .semibold))
                        .foregroundStyle(.ink)
                        .lineLimit(1)
                    if let mark = state.mark(at: .now) {
                        Text(mark.word).font(.caption2.weight(.medium)).foregroundStyle(Color.lateInk)
                    }
                    Spacer(minLength: 6)
                    Text(ChatGroups.when(thread.lastAt))
                        .font(.caption2)
                        .foregroundStyle(thread.unread > 0 ? Color.sageText : .inkFaint)
                }
                HStack(alignment: .top, spacing: 8) {
                    Text(ChatGroups.line(thread, running: state))
                        .font(.footnote)
                        .foregroundStyle(thread.unread > 0 ? Color.ink : .inkMuted)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if thread.unread > 0 {
                        UnreadBadge(count: thread.unread)
                    }
                }
            }
            .animation(Motion.settle, value: state.state)
            .animation(Motion.pop, value: thread.unread)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat-card")
        .contextMenu {
            Button { open(thread.agentId) } label: { Label("Open thread", systemImage: "bubble.left.and.text.bubble.right") }
            Button { details(thread.agentId) } label: { Label("Agent details", systemImage: "info.circle") }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
