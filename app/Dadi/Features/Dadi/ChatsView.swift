import SwiftUI

/// Chats: every conversation as a glass card, in groups where the first match
/// wins: NEEDS YOU (an agent whose helper is asking), WORKING NOW, UNREAD and
/// EARLIER, under a search field. Talking to Dadi is the dock, not this page.
struct ChatsView: View {
    let threads: [ThreadSummary]
    /// Each agent's running lanes.
    let lanes: (String) -> Set<Lane>
    /// The helper tasks asking their agent, by owner.
    let asking: [String: NasTask]
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

    private struct Group: Identifiable {
        let title: String
        let threads: [ThreadSummary]
        var id: String { title }
    }

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
                } else if groups.isEmpty {
                    Text("No chat matches \u{201C}\(query)\u{201D}.")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 8)
                } else {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption2.weight(.semibold))
                                .tracking(1.4)
                                .foregroundStyle(group.title == "NEEDS YOU" ? Color.clay : .inkFaint)
                                .padding(.horizontal, 6)
                                .padding(.top, 6)
                            GlassEffectContainer(spacing: 8) {
                                VStack(spacing: 8) { ForEach(group.threads) { card($0) } }
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
        .animation(Motion.settle, value: groups.map(\.id))
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

    /// The groups, in priority order; a thread sits in the first that fits.
    private var groups: [Group] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = threads.filter { needle.isEmpty || $0.agentName.lowercased().contains(needle) }
        let needs = shown.filter { asking[$0.agentId] != nil }
        let rest = shown.filter { asking[$0.agentId] == nil }
        return [
            Group(title: "NEEDS YOU", threads: needs),
            Group(title: "WORKING NOW", threads: rest.filter { !lanes($0.agentId).isEmpty }),
            Group(title: "UNREAD", threads: rest.filter { lanes($0.agentId).isEmpty && $0.unread > 0 }),
            Group(title: "EARLIER", threads: rest.filter { lanes($0.agentId).isEmpty && $0.unread == 0 }),
        ].filter { !$0.threads.isEmpty }
    }

    private func card(_ thread: ThreadSummary) -> some View {
        let running = lanes(thread.agentId)
        let task = asking[thread.agentId]
        return Button { open(thread.agentId) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ThreadRow(thread: thread, lanes: running, unread: thread.unread)
                if let task {
                    Label(task.state, systemImage: "exclamationmark.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.clay)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(task == nil ? Color.clear : Color.clay.opacity(0.1), in: .rect(cornerRadius: 20, style: .continuous))
            .laneSheen(running.contains(.work), in: .rect(cornerRadius: 20, style: .continuous))
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
