import SwiftUI

/// One agent's thread: its history by day, live replies from Hath's events,
/// thaali's lane pill over the composer while the agent thinks or works, a
/// caret beside it that returns to the newest message once the thread is
/// scrolled up, and the composer to reply as Ankur. Agent text runs the full
/// width on the field as rendered markdown and scrolls up under the bars;
/// Ankur's words are sage bubbles. Holding a message lifts it with Copy,
/// Reply with quote, Share and, for the agent's, its activity; swiping one
/// right quotes it too. A quote waits over the composer and goes out as a
/// blockquote ahead of the reply.
struct ThreadView: View {
    let hath: HathClient
    let agentId: String
    let name: String
    /// The newest event from Home's stream; messages for this agent are added.
    let live: HathEvent?
    /// The agent's lanes running now.
    let lanes: Set<Lane>
    /// Changes each time Home's event stream reconnects; the thread reloads to
    /// catch what arrived while it was down.
    let connections: Int
    /// Ankur has seen the thread through this message.
    let read: (Int) -> Void
    /// Opens the agent's sheet, where its activity is.
    let details: () -> Void

    @State private var messages: [DurableMessage] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var sendError: String?
    @State private var draft = ""
    @State private var photos: [DraftPhoto] = []
    @State private var sending = false
    /// The message being replied to, quoted ahead of the reply.
    @State private var quote: DurableMessage?
    @State private var quoted = 0
    @State private var sent = 0
    @State private var received = 0
    @Namespace private var glass
    @State private var position = ScrollPosition(edge: .bottom)
    /// True while the end of the thread is off screen.
    @State private var awayFromBottom = false

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
                        .modifier(QuoteSwipe(enabled: message.kind != .notice, fromUser: message.fromUser) { reply(to: message) })
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: message.fromUser ? .bottomTrailing : .bottomLeading)), removal: .opacity))
                }
                Color.clear
                    .frame(height: 24)
                    .onScrollVisibilityChange(threshold: 0.01) { visible in
                        awayFromBottom = !visible
                    }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .animation(Motion.settle, value: messages)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($position)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectHidden(true, for: .bottom)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 10) {
                        if awayFromBottom {
                            Button {
                                withAnimation(Motion.settle) { position.scrollTo(edge: .bottom) }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.sageText)
                                    .frame(width: LaneChip.height, height: LaneChip.height)
                                    .contentShape(.circle)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.tint(Color.bone.opacity(0.6)).interactive(), in: .circle)
                            .glassEffectID("caret", in: glass)
                            .accessibilityLabel("Scroll to newest message")
                        }
                        LaneChip(lanes: lanes, glass: glass)
                    }
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.82), value: awayFromBottom)
                if let sendError {
                    Label(sendError, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.danger)
                        .transition(.opacity)
                }
                if let quote {
                    QuoteCard(message: quote, author: quote.fromUser ? "You" : name) {
                        withAnimation(Motion.snap) { self.quote = nil }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                Composer(text: $draft, photos: $photos, placeholder: "Message \(name)…", busy: sending, lanes: lanes, send: send)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .composerInset()
        }
        .navigationTitle(name)
        .animation(Motion.snap, value: quote)
        .sensoryFeedback(.impact(weight: .light), trigger: sent)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: quoted)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: received)
        .task(id: connections) { await load() }
        .onChange(of: live) { _, event in
            guard case .message(let id, let message)? = event, id == agentId else { return }
            if insert(message), !message.fromUser { received += 1 }
            read(message.seq)
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
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
            bubble(message, opensGroup: opensGroup)
        } else {
            bubble(message, opensGroup: opensGroup)
                .contextMenu {
                    Button { UIPasteboard.general.string = message.content } label: { Label("Copy", systemImage: "doc.on.doc") }
                    Button { reply(to: message) } label: { Label("Reply with quote", systemImage: "arrowshape.turn.up.left") }
                    ShareLink(item: message.content) { Label("Share", systemImage: "square.and.arrow.up") }
                    if !message.fromUser {
                        Button(action: details) { Label("Show activity", systemImage: "clock.arrow.circlepath") }
                    }
                }
        }
    }

    @ViewBuilder
    private func bubble(_ message: DurableMessage, opensGroup: Bool) -> some View {
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
                    Text(InlineMarkdown.attributed(message.content))
                        .font(.body)
                        .foregroundStyle(.bone)
                        .tint(.bone)
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
                    Text(name).font(.footnote.weight(.semibold)).foregroundStyle(.inkMuted)
                }
                AgentMarkdown(source: message.content)
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
                    AttachmentView(file: file, hath: hath)
                }
            }
        }
    }

    private func load() async {
        do {
            messages = try await hath.messages(agentId: agentId)
            loadError = nil
            if let newest = messages.last { read(newest.seq) }
        } catch is CancellationError {
            return
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

    /// Quotes `message` over the composer.
    private func reply(to message: DurableMessage) {
        quoted += 1
        withAnimation(Motion.snap) { quote = message }
    }

    private func send() {
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attached = photos
        guard !words.isEmpty || !attached.isEmpty, !sending else { return }
        let content = quote.map { QuoteCard.blockquote($0.content) + words } ?? words
        sending = true
        sendError = nil
        Task {
            defer { sending = false }
            do {
                let reply = try await hath.send(content, to: agentId, attachments: attached.map(\.outbound))
                draft = ""
                photos = []
                quote = nil
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

/// A message being replied to, over the composer: who wrote it and its first
/// lines, with a button to drop it.
private struct QuoteCard: View {
    let message: DurableMessage
    let author: String
    let dismiss: () -> Void

    /// How much of a message a quote carries.
    private static let quotedCharacters = 280

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.sageText)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to \(author)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.sageText)
                Text(Agent.preview(message.content))
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.inkFaint)
                    .frame(width: 26, height: 26)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Don't quote")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 680)
        .glassEffect(.regular.tint(Color.bone.opacity(0.5)), in: .rect(cornerRadius: 18, style: .continuous))
    }

    /// `content`'s opening as a markdown blockquote, ahead of a reply.
    static func blockquote(_ content: String) -> String {
        let text = content.count > quotedCharacters ? String(content.prefix(quotedCharacters)) + "…" : content
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n") + "\n\n"
    }
}

/// Swiping a message right to quote it: the message follows the finger with
/// a reply arrow growing in behind it, and letting go past the mark quotes
/// it. A vertical scroll is left alone.
private struct QuoteSwipe: ViewModifier {
    let enabled: Bool
    /// Ankur's own bubbles sit on the right, so their arrow shows at their left edge.
    let fromUser: Bool
    let quote: () -> Void

    @State private var offset: CGFloat = 0

    /// How far the message travels before letting go quotes it.
    private let reach: CGFloat = 64

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: fromUser ? .center : .leading) {
                if offset > 0 {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(offset >= reach ? Color.bone : .sageText)
                        .frame(width: 32, height: 32)
                        .background(offset >= reach ? Color.sageDeep : .sage.opacity(0.16), in: .circle)
                        .scaleEffect(0.5 + 0.5 * min(1, offset / reach))
                        .opacity(min(1, offset / (reach * 0.6)))
                        .animation(Motion.snap, value: offset >= reach)
                        .padding(.leading, fromUser ? 0 : 4)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { drag in
                        guard enabled, drag.translation.width > 0, abs(drag.translation.width) > abs(drag.translation.height) * 1.4 else { return }
                        offset = min(reach * 1.4, drag.translation.width * 0.7)
                    }
                    .onEnded { _ in
                        if offset >= reach { quote() }
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) { offset = 0 }
                    }
            )
            .sensoryFeedback(.selection, trigger: offset >= reach)
    }
}
