import SwiftUI

/// Between joining and Home: the wordmark rests centred on the field with one
/// quiet status line under it while the node logs in and Hath answers, or the
/// shared error card says why dadi can't be reached. Nothing moves when the
/// status changes, and Home fades in over it when dadi answers.
struct ConnectingView: View {
    let connection: Connection
    let wordmark: Namespace.ID

    private static let wordmarkSize: CGFloat = 84

    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            FieldBloom()
            switch connection.state {
            case .failed(let message):
                failure(message)
            case .connecting(let detail):
                connecting(detail)
            case .needsSetup, .online:
                EmptyView()
            }
        }
    }

    /// The line under the mark: Hath's own progress words when it has any.
    nonisolated static func status(detail: String?) -> String {
        detail ?? "Connecting to dadi"
    }

    private func connecting(_ detail: String?) -> some View {
        ZStack {
            Text("દાદી")
                .font(.wordmark(Self.wordmarkSize))
                .inkCentered(.word, size: Self.wordmarkSize)
                .foregroundStyle(.sageDeep)
                .opacity(breathing ? 1 : 0.62)
                .matchedGeometryEffect(id: "wordmark", in: wordmark)
                .onAppear {
                    guard !reduceMotion else { breathing = true; return }
                    withAnimation(Motion.breath) { breathing = true }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            VStack(spacing: 4) {
                Text(Self.status(detail: detail))
                    .font(.callout)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .contentTransition(.opacity)
                    .animation(Motion.settle, value: detail)
                if let name = connection.nodeName {
                    Text(name)
                        .font(.footnote)
                        .foregroundStyle(.inkFaint)
                }
            }
            .frame(maxWidth: 320, alignment: .top)
            .frame(height: 80, alignment: .top)
            .offset(y: Self.wordmarkSize + 8)
        }
        .overlay(alignment: .bottom) {
            Button("Forget this device") { connection.forget() }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(.inkFaint)
                .focusEffectDisabled()
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
        .transition(.opacity)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 14) {
            ErrorCard(service: "dadi", status: nil, message: message) {
                withAnimation(Motion.settle) { connection.retry() }
            }
            Button("Forget this device", role: .destructive) { connection.forget() }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(.inkFaint)
                .focusEffectDisabled()
        }
        .frame(maxWidth: 460)
        .padding(24)
        .transition(.opacity)
    }
}
