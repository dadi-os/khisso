import SwiftUI

/// The Dadi tab's drawer: Talk to Dadi, a search over the agents, the agents
/// working now, then every other thread, newest first, each with its unread
/// count. A long press on a row offers its thread and the agent's details.
/// Rows take no swipes: a sideways drag in the drawer closes it.
struct AgentsDrawer: View {
    let store: HomeStore
    let page: HomeView.Page
    let choose: (HomeView.Page) -> Void
    /// Opens an agent's sheet.
    let details: (String) -> Void

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            talkToDadi
                .padding(.horizontal, 8)
            search
                .padding(.horizontal, 14)
                .padding(.top, 12)
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            }
            let (working, rest) = sections
            if !working.isEmpty {
                section("WORKING NOW", working)
            }
            if !rest.isEmpty {
                section(working.isEmpty ? "AGENTS" : "EVERYONE ELSE", rest)
            }
            if !query.isEmpty && working.isEmpty && rest.isEmpty {
                Text("No agent matches \u{201C}\(query)\u{201D}.")
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
            }
        }
        .animation(Motion.settle, value: store.threads.map(\.agentId))
        .animation(Motion.settle, value: store.running)
        .animation(Motion.snap, value: query)
    }

    /// The threads matching the search, split into agents working now and the rest.
    private var sections: ([ThreadSummary], [ThreadSummary]) {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = store.threads.filter { needle.isEmpty || $0.agentName.lowercased().contains(needle) }
        return (shown.filter { store.running.contains($0.agentId) }, shown.filter { !store.running.contains($0.agentId) })
    }

    private var talkToDadi: some View {
        Button { choose(.dadi) } label: {
            HStack(spacing: 12) {
                ZStack {
                    if store.routing {
                        PulseOut()
                    }
                    Text("દ")
                        .font(.wordmark(21))
                        .foregroundStyle(store.routing ? Color.sageDeep : .sageText)
                        .inkCentered(.letter, size: 21)
                        .frame(width: 34, height: 34)
                        .background(.sage.opacity(page == .dadi || store.routing ? 0.26 : 0.14), in: .circle)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Talk to Dadi")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.ink)
                    if store.routing {
                        HStack(spacing: 6) {
                            ThinkingMark()
                            Text("routing").font(.footnote).foregroundStyle(.sageText)
                        }
                        .transition(.opacity)
                    } else {
                        Text("Start something new")
                            .font(.footnote)
                            .foregroundStyle(.inkFaint)
                            .transition(.opacity)
                    }
                }
                Spacer()
            }
            .animation(Motion.settle, value: store.routing)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(page == .dadi ? Color.sage.opacity(0.14) : .clear, in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.inkFaint)
            TextField("Search \(store.threads.count) agents", text: $query)
                .font(.subheadline)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.bone.opacity(0.55), in: .rect(cornerRadius: 12, style: .continuous))
    }

    private func section(_ title: String, _ threads: [ThreadSummary]) -> some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.inkFaint)
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 6)
            ForEach(threads) { thread in
                row(thread)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .padding(.horizontal, 8)
    }

    private func row(_ thread: ThreadSummary) -> some View {
        let selected = page == .thread(thread.agentId)
        let lanes = store.lanes(of: thread.agentId)
        return Button { choose(.thread(thread.agentId)) } label: {
            ThreadRow(thread: thread, lanes: lanes, unread: thread.unread)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? Color.sage.opacity(0.14) : .clear, in: .rect(cornerRadius: 16))
                .laneSheen(lanes.contains(.reasoning), in: .rect(cornerRadius: 16))
                .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { choose(.thread(thread.agentId)) } label: { Label("Open thread", systemImage: "bubble.left.and.text.bubble.right") }
            Button { details(thread.agentId) } label: { Label("Agent details", systemImage: "info.circle") }
        } preview: {
            ThreadRow(thread: thread, lanes: lanes, unread: thread.unread)
                .padding(16)
                .frame(width: 300)
                .background(Color.boneRaised)
        }
    }
}

/// Thaali's live ring: a sage disc swelling out and fading behind a busy mark.
private struct PulseOut: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(.sage.opacity(0.45))
            .frame(width: 34, height: 34)
            .phaseAnimator([false, true]) { ring, out in
                ring.scaleEffect(out ? 1.55 : 1).opacity(out ? 0 : 0.55)
            } animation: { out in
                out && !reduceMotion ? .easeOut(duration: 2.4) : nil
            }
    }
}
