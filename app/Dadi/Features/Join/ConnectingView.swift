import SwiftUI

/// Between joining and Home: only the દાદી mark, ink-centred on the full screen
/// and breathing, while the node logs in and Hath answers, or the shared error
/// card says why dadi can't be reached. After `forgetDelay` of still connecting,
/// a quiet "Forget this device" fades in at the bottom without moving the mark.
/// Home fades in over it when dadi answers.
struct ConnectingView: View {
    let connection: Connection
    let wordmark: Namespace.ID

    /// How long the connection may stay pending before Forget this device appears.
    static let forgetDelay: Duration = .seconds(8)

    private static let wordmarkSize: CGFloat = 84

    @State private var breathing = false
    @State private var offersForget = false
    @State private var confirmingForget = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            FieldBloom()
            switch connection.state {
            case .failed(let message):
                failure(message)
            case .connecting:
                connecting
            case .needsSetup, .online:
                EmptyView()
            }
        }
        .confirmationDialog("Forget this device?", isPresented: $confirmingForget, titleVisibility: .visible) {
            Button("Forget this device", role: .destructive) { connection.forget() }
        } message: {
            Text("dadi will need a new setup code to join again.")
        }
    }

    private var connecting: some View {
        Text("દાદી")
            .font(.wordmark(Self.wordmarkSize))
            .inkCentered(.word, size: Self.wordmarkSize)
            .foregroundStyle(.sageDeep)
            .shadow(color: .sage.opacity(breathing ? 0.55 : 0.1), radius: breathing ? 30 : 8)
            .scaleEffect(breathing ? 1.02 : 0.98)
            .accessibilityLabel("Dadi, connecting")
            .accessibilityIdentifier("connecting-wordmark")
            .matchedGeometryEffect(id: "wordmark", in: wordmark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("Forget this device") { confirmingForget = true }
                    .buttonStyle(.plain)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.inkMuted)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 16)
                    .contentShape(.rect)
                    .focusEffectDisabled()
                    .accessibilityIdentifier("connecting-forget")
                    .padding(.bottom, 12)
                    .opacity(offersForget ? 1 : 0)
                    .allowsHitTesting(offersForget)
                    .accessibilityHidden(!offersForget)
            }
            .transition(.opacity)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Motion.breath) { breathing = true }
            }
            .task {
                do { try await Task.sleep(for: Self.forgetDelay) } catch { return }
                withAnimation(Motion.settle) { offersForget = true }
            }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 14) {
            ErrorCard(service: "dadi", status: nil, message: message) {
                withAnimation(Motion.settle) { connection.retry() }
            }
            Button("Forget this device", role: .destructive) { confirmingForget = true }
                .buttonStyle(.plain)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)
                .focusEffectDisabled()
        }
        .frame(maxWidth: 460)
        .padding(24)
        .transition(.opacity)
    }
}
