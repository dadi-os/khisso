import SwiftUI

/// Talk to Dadi: your words go to the router, which sends them on as you to the
/// agent that owns them. While it works this is a waiting room: the words lift
/// out of the composer above it, the wordmark breathes, and once the router has
/// sent them it says to whom before that thread opens. Arriving from
/// Connecting, the wordmark stays where it was and the rest fades in around it.
struct DadiView: View {
    /// The idle wordmark's size, which Connecting shares so the mark does not
    /// change size as Home arrives.
    static let wordmarkSize: CGFloat = 84

    let hath: HathClient
    let wordmark: Namespace.ID
    /// Opens the thread of the agent the router handed off to.
    let open: (String) -> Void

    /// Where a hand-off is.
    private enum Stage: Equatable {
        case idle
        case routing(String)
        case sent(words: String, to: String)
    }

    @State private var draft = ""
    @State private var stage: Stage = .idle
    @State private var problem: String?
    @State private var glow = false
    @State private var handedOff = 0
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 22) {
                Text("દાદી")
                    .font(.wordmark(stage == .idle ? Self.wordmarkSize : 56))
                    .inkCentered(.word, size: stage == .idle ? Self.wordmarkSize : 56)
                    .foregroundStyle(.sageDeep)
                    .shadow(color: .sage.opacity(stage == .idle ? 0 : (glow ? 0.5 : 0.1)), radius: glow ? 24 : 8)
                    .matchedGeometryEffect(id: "wordmark", in: wordmark)
                switch stage {
                case .idle:
                    VStack(spacing: 8) {
                        Text(greeting)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.ink)
                        Text("Tell Dadi what you need. It lands with the agent who owns it, and that chat opens.")
                            .font(.callout)
                            .foregroundStyle(.inkMuted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
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
            Spacer()
            Composer(text: $draft, placeholder: "Message Dadi…", busy: stage != .idle, lanes: stage == .idle ? [] : [.conversation], send: handOff)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .opacity(arrived ? 1 : 0)
                .offset(y: arrived ? 0 : 16)
        }
        .onAppear { withAnimation(Motion.settle.delay(0.3)) { arrived = true } }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: stage)
        .sensoryFeedback(.success, trigger: handedOff)
        .navigationTitle("Dadi")
    }

    private var status: some View {
        Group {
            switch stage {
            case .sent(_, let agent):
                Label("Sent to \(Agent.displayName(agent))", systemImage: "checkmark.circle.fill")
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
        guard !text.isEmpty, stage == .idle else { return }
        draft = ""
        problem = nil
        stage = .routing(text)
        Task {
            do {
                let response = try await hath.route(text)
                guard let first = response.messages.first else {
                    stage = .idle
                    draft = text
                    problem = "Dadi didn't send this anywhere."
                    return
                }
                stage = .sent(words: text, to: first.toAgentId)
                handedOff += 1
                try await Task.sleep(for: .milliseconds(900))
                open(first.toAgentId)
                stage = .idle
            } catch {
                stage = .idle
                draft = text
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
