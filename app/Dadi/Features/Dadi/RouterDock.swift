import SwiftUI

/// The router's one lane as the dock sees it: Ankur's draft, whether the
/// composer is open, and what the last send did. Chats' list, the tab bar's
/// accessory and the composer over the page all read it.
@MainActor
@Observable
final class RouterDock {
    /// What the capsule says it is doing.
    enum Stage: Equatable {
        case idle
        /// This device's words are with the router.
        case routing(String)
        /// The router sent the words to this agent.
        case sent(to: String)
    }

    var draft = ""
    var photos: [DraftPhoto] = []
    /// True while the composer is open over the page.
    var composing = false
    private(set) var stage = Stage.idle
    /// The router's own words for a failed run, shown above the returned draft.
    private(set) var problem: String?
    private(set) var handedOff = 0

    /// Opens the composer, starting it with `words` when it is empty.
    func compose(_ words: String = "") {
        if draft.isEmpty { draft = words }
        problem = nil
        composing = true
    }

    /// Hands the draft to the router. `sent` runs with each message the router
    /// sent, once it is done; a run that sent nothing is a valid outcome and
    /// leaves the dock quiet.
    func send(_ hath: HathClient, sent: @escaping @MainActor ([RoutedMessage]) -> Void) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attached = photos
        guard !text.isEmpty || !attached.isEmpty, stage == .idle else { return }
        let shown = text.isEmpty ? "\(attached.count) photo\(attached.count == 1 ? "" : "s")" : text
        draft = ""
        photos = []
        problem = nil
        composing = false
        stage = .routing(shown)
        Task {
            do {
                let response = try await hath.route(text, attachments: attached.map(\.outbound))
                if let first = response.messages.first {
                    stage = .sent(to: first.toAgentId)
                    handedOff += 1
                    sent(response.messages)
                    do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
                }
                stage = .idle
            } catch {
                stage = .idle
                draft = text
                photos = attached
                problem = error.localizedDescription
                composing = true
            }
        }
    }
}

/// The router's mark: a ring around the Gujarati da, with a sage arc turning
/// around it while a run is active.
struct RouterMark: View {
    let active: Bool
    var size: CGFloat = 26

    @State private var turn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.sageLine, lineWidth: 1.5)
            if active {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Color.sage, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .padding(1)
                    .rotationEffect(.degrees(turn ? 360 : 0))
            }
            Text("દ")
                .font(.wordmark(size * 0.55, weight: .semibold))
                .inkCentered(.letter, size: size * 0.55)
                .foregroundStyle(.sageDeep)
        }
        .frame(width: size, height: size)
        .onChange(of: active, initial: true) {
            turn = false
            guard active, !reduceMotion else { return }
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { turn = true }
        }
        .accessibilityHidden(true)
    }
}

/// The dock: a glass capsule above the tab bar that opens the composer. It says
/// what the router is doing, whichever device started it.
struct RouterDockBar: View {
    let dock: RouterDock
    /// True while any router run is in flight, here or on another device.
    let active: Bool
    /// False while dadi is out of reach: the dock dims and cannot be opened.
    let online: Bool
    /// An agent's name, for "Sent to".
    let name: (String) -> String

    var body: some View {
        Button { dock.compose() } label: {
            HStack(spacing: 10) {
                RouterMark(active: active)
                Text(title)
                    .font(.body)
                    .foregroundStyle(online ? (dock.stage == .idle && dock.draft.isEmpty && !active ? Color.inkMuted : .ink) : .inkFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if let trailing {
                    HStack(spacing: 4) {
                        if case .sent = dock.stage { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                        Text(trailing).font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(.sageText)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!online)
        .opacity(online ? 1 : 0.6)
        .animation(Motion.snap, value: dock.stage)
        .accessibilityLabel(title)
        .accessibilityHint(online ? "Opens the message field" : "")
    }

    private var title: String {
        if !online { return "dadi is offline" }
        switch dock.stage {
        case .routing(let words): return words
        case .sent(let agent): return "Sent to \(name(agent))"
        case .idle:
            if !dock.draft.isEmpty { return dock.draft }
            return active ? "Dadi is routing" : "Message Dadi…"
        }
    }

    private var trailing: String? {
        guard online else { return nil }
        switch dock.stage {
        case .routing: return "Routing"
        case .sent: return nil
        case .idle: return !dock.draft.isEmpty ? "Draft" : active ? "Routing" : nil
        }
    }
}

/// The composer over the page: the page dims, the field sits above the keyboard
/// with a "Dadi" chip over it, and the router's own words show above it when a
/// run failed. A second send waits while the router is active.
struct RouterCompose: View {
    @Bindable var dock: RouterDock
    let active: Bool
    let send: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { dock.composing = false }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    RouterMark(active: active, size: 20)
                    Text("Dadi").font(.footnote.weight(.semibold)).foregroundStyle(.ink)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                if let problem = dock.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.danger)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
                }
                Composer(text: $dock.draft, photos: $dock.photos, placeholder: "Message Dadi…", busy: active, focusOnAppear: true, send: send)
                if active {
                    Text("Available when Dadi has finished routing")
                        .font(.caption)
                        .foregroundStyle(.inkMuted)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .transition(.opacity)
    }
}
