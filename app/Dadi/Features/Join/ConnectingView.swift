import SwiftUI

/// Between joining and Home: the wordmark breathes on the field while the node
/// logs in and Hath answers, or a glass card says why dadi can't be reached.
struct ConnectingView: View {
    let connection: Connection
    let wordmark: Namespace.ID

    @State private var glow = false
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

    private func connecting(_ detail: String?) -> some View {
        VStack(spacing: 28) {
            Spacer()
            Text("દાદી")
                .font(.wordmark(96))
                .inkCentered(.word, size: 96)
                .foregroundStyle(.sageDeep)
                .shadow(color: .sage.opacity(glow ? 0.55 : 0.05), radius: glow ? 28 : 6)
                .scaleEffect(glow ? 1.02 : 0.98)
                .matchedGeometryEffect(id: "wordmark", in: wordmark)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(Motion.breath) { glow = true }
                }
            VStack(spacing: 10) {
                Text("Connecting to dadi")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.ink)
                Text(detail ?? "Logging in to your box…")
                    .font(.callout)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .contentTransition(.opacity)
                    .animation(Motion.settle, value: detail)
                    .frame(maxWidth: 340)
                if let name = connection.nodeName {
                    Label(name, systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.sageText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.sage.opacity(0.12), in: .capsule)
                        .padding(.top, 6)
                }
            }
            Spacer()
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
        VStack(spacing: 18) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.clay)
                .symbolEffect(.wiggle, options: .nonRepeating)
            Text("Can't reach dadi")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.ink)
            Text(message)
                .font(.callout)
                .foregroundStyle(.inkMuted)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Button("Forget this device", role: .destructive) { connection.forget() }
                    .buttonStyle(.glass)
                Button {
                    withAnimation(Motion.settle) { connection.retry() }
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.glassProminent)
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(24)
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }
}
