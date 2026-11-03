import SwiftUI

/// The router's one lane as the dock sees it: Ankur's draft, whether the
/// composer is open, and whether his words are with the router. Chats' list,
/// the tab bar's accessory and the composer over the page all read it.
@MainActor
@Observable
final class RouterDock {
    var draft = ""
    var photos: [DraftPhoto] = []
    /// True while the composer is open over the page.
    var composing = false
    /// True while this device's words are with the router.
    private(set) var sending = false
    private(set) var handedOff = 0

    /// Opens the composer, starting it with `words` when it is empty.
    func compose(_ words: String = "") {
        if draft.isEmpty { draft = words }
        composing = true
    }

    /// Hands the draft to the router. `sent` runs with each message the router
    /// sent, once it is done; a run that sent nothing is a valid outcome and
    /// leaves the dock quiet. `failed` runs with the router's own words after
    /// the draft is back in the composer.
    func send(_ hath: HathClient, sent: @escaping @MainActor ([RoutedMessage]) -> Void, failed: @escaping @MainActor (String) -> Void) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attached = photos
        guard !text.isEmpty || !attached.isEmpty, !sending else { return }
        draft = ""
        photos = []
        composing = false
        sending = true
        Task {
            defer { sending = false }
            do {
                let response = try await hath.route(text, attachments: attached.map(\.outbound))
                if !response.messages.isEmpty {
                    handedOff += 1
                    sent(response.messages)
                }
            } catch {
                draft = text
                photos = attached
                failed(error.localizedDescription)
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
    var body: some View {
        Button { dock.compose() } label: {
            HStack(spacing: 10) {
                RouterMark(active: active)
                Text(title)
                    .font(.body)
                    .foregroundStyle(online ? (dock.draft.isEmpty ? Color.inkMuted : .ink) : .inkFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!online)
        .opacity(online ? 1 : 0.6)
        .accessibilityLabel(title)
        .accessibilityHint(online ? "Opens the message field" : "")
    }

    private var title: String {
        if !online { return "dadi is offline" }
        return dock.draft.isEmpty ? "Talk to Dadi" : dock.draft
    }
}

/// The composer over the page: the page dims and the field sits above the keyboard.
/// A second send waits while the router is active.
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
