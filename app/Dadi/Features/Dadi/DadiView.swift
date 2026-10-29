import SwiftUI

/// Talk to Dadi: your words go to the router, which sends them on as you to the
/// agent that owns them. At rest the wordmark breathes over a greeting, a chip
/// says how many agents are working (it opens the drawer), and the threads
/// with replies you have not read, or else the latest ones, wait below; they
/// step aside while you type. While the router works this is a waiting room:
/// the words lift out of the composer above it, the wordmark glows, and once
/// the router has sent them it says to whom before that thread opens.
/// Arriving from Connecting, the wordmark stays where it was and the rest
/// fades in around it.
struct DadiView: View {
    /// The idle wordmark's size, which Connecting shares so the mark does not
    /// change size as Home arrives.
    static let wordmarkSize: CGFloat = 84

    /// How many threads wait under the greeting.
    private static let shownThreads = 3

    let hath: HathClient
    /// Every thread, newest first, as Home has them.
    let threads: [ThreadSummary]
    /// Each agent's running lanes.
    let lanes: (String) -> Set<Lane>
    /// An agent's name as Hath names it, for "Sent to".
    let name: (String) -> String
    let wordmark: Namespace.ID
    /// Opens the thread of an agent: the one the router handed off to, or a
    /// row tapped.
    let open: (String) -> Void
    /// Opens an agent's sheet.
    let details: (String) -> Void
    /// Opens the drawer, where the working agents are.
    let openDrawer: () -> Void
    /// Words the composer starts with, as when Dadi is told about a session.
    var opening = ""
    /// Puts the cursor in the composer as the page opens.
    var focusComposer = false

    /// Where a hand-off is.
    private enum Stage: Equatable {
        case idle
        case routing(String)
        case sent(words: String, to: String)
    }

    @State private var draft = ""
    @State private var photos: [DraftPhoto] = []
    @State private var stage: Stage = .idle
    @State private var problem: String?
    @State private var glow = false
    @State private var handedOff = 0
    @State private var arrived = false
    @State private var typing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(spacing: 20) {
                Text("દાદી")
                    .font(.wordmark(stage == .idle ? Self.wordmarkSize : 56))
                    .inkCentered(.word, size: stage == .idle ? Self.wordmarkSize : 56)
                    .foregroundStyle(.sageDeep)
                    .shadow(color: .sage.opacity(stage == .idle ? 0 : (glow ? 0.5 : 0.1)), radius: glow ? 24 : 8)
                    .phaseAnimator([false, true]) { mark, inhale in
                        mark.scaleEffect(stage == .idle && inhale && !reduceMotion ? 1.025 : 1)
                    } animation: { _ in .easeInOut(duration: 2.4) }
                    .matchedGeometryEffect(id: "wordmark", in: wordmark)
                switch stage {
                case .idle:
                    VStack(spacing: 12) {
                        Text(greeting)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.ink)
                        if threads.isEmpty {
                            Text("Tell Dadi what you need. It lands with the agent who owns it, and that chat opens.")
                                .font(.callout)
                                .foregroundStyle(.inkMuted)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 320)
                        }
                        if !working.isEmpty && !typing {
                            workingChip
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .opacity(arrived ? 1 : 0)
                    .offset(y: arrived ? 0 : 10)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                case .routing(let text), .sent(let text, _):
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.bone)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(.sageDeep, in: .rect(cornerRadius: 20, style: .continuous))
                        .frame(maxWidth: 360)
                        .transition(.asymmetric(
                            insertion: .offset(y: 260).combined(with: .scale(scale: 0.7, anchor: .bottom)).combined(with: .opacity),
                            removal: .opacity
                        ))
                    status
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(.danger)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 24)
            if stage == .idle && !typing && !waiting.isEmpty {
                waitingList
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .opacity(arrived ? 1 : 0)
                    .transition(.opacity.combined(with: .offset(y: 12)))
            }
            Composer(text: $draft, photos: $photos, placeholder: "Message Dadi…", busy: stage != .idle, lanes: stage == .idle ? [] : [.process], focusOnAppear: focusComposer, send: handOff)
                .padding(.horizontal, 16)
                .composerInset()
                .opacity(arrived ? 1 : 0)
                .offset(y: arrived ? 0 : 16)
        }
        .onAppear {
            if draft.isEmpty { draft = opening }
            withAnimation(Motion.settle.delay(0.3)) { arrived = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(Motion.snap) { typing = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(Motion.settle) { typing = false }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: stage)
        .animation(Motion.settle, value: waiting.map(\.agentId))
        .animation(Motion.settle, value: working.count)
        .sensoryFeedback(.success, trigger: handedOff)
        .navigationTitle("Dadi")
    }

    /// Agents with a lane running.
    private var working: [ThreadSummary] {
        threads.filter { !lanes($0.agentId).isEmpty }
    }

    /// Threads with replies not yet read, or the newest when there are none.
    private var waiting: [ThreadSummary] {
        let unread = threads.filter { $0.unread > 0 }
        return Array((unread.isEmpty ? threads : unread).prefix(Self.shownThreads))
    }

    /// "2 agents working" in a pill that runs the working sheen; it opens the drawer.
    private var workingChip: some View {
        Button(action: openDrawer) {
            HStack(spacing: 8) {
                ProcessingMark()
                Text(working.count == 1 ? "\(working[0].agentName) is working" : "\(working.count) agents working")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.sageText)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.sage.opacity(0.12), in: .capsule)
            .laneSheen(true, in: Capsule())
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the drawer")
    }

    /// The waiting threads: unread first, else the newest, each opening its
    /// thread, with its menu on a long press.
    private var waitingList: some View {
        let unread = threads.contains { $0.unread > 0 }
        return VStack(alignment: .leading, spacing: 8) {
            Text(unread ? "UNREAD" : "RECENT")
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.inkFaint)
                .padding(.horizontal, 6)
            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(waiting) { thread in
                        Button { open(thread.agentId) } label: {
                            ThreadRow(thread: thread, lanes: lanes(thread.agentId), unread: thread.unread)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .laneSheen(lanes(thread.agentId).contains(.work), in: .rect(cornerRadius: 20, style: .continuous))
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
            }
        }
        .frame(maxWidth: 680)
    }

    private var status: some View {
        Group {
            switch stage {
            case .sent(_, let agent):
                Label("Sent to \(name(agent))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.sageDeep)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            default:
                Label("Finding the right agent", systemImage: "arrow.triangle.branch")
                    .foregroundStyle(.inkMuted)
                    .symbolEffect(.pulse)
                    .modifier(Shimmer(active: !reduceMotion))
                    .transition(.opacity)
            }
        }
        .font(.callout.weight(.medium))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Motion.breath) { glow = true }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Still up?"
        }
    }

    private func handOff() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attached = photos
        guard !text.isEmpty || !attached.isEmpty, stage == .idle else { return }
        let shown = text.isEmpty ? "\(attached.count) photo\(attached.count == 1 ? "" : "s")" : text
        draft = ""
        photos = []
        problem = nil
        stage = .routing(shown)
        Task {
            do {
                let response = try await hath.route(text, attachments: attached.map(\.outbound))
                guard let first = response.messages.first else {
                    stage = .idle
                    draft = text
                    photos = attached
                    problem = "Dadi didn't send this anywhere."
                    return
                }
                stage = .sent(words: shown, to: first.toAgentId)
                handedOff += 1
                try await Task.sleep(for: .milliseconds(900))
                open(first.toAgentId)
                stage = .idle
            } catch {
                stage = .idle
                draft = text
                photos = attached
                problem = error.localizedDescription
            }
        }
    }
}

/// Sweeps a soft band of light across the content while `active`, for work in
/// progress.
private struct Shimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, .bone.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.5)
                            .offset(x: phase * proxy.size.width * 1.5)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard active else { return }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}
