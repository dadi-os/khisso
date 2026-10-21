import SwiftUI

/// Talk to Dadi: the દ mark is the button. Tap it to dictate or scribble, and
/// the words go to the router through the iPhone; the page follows them until
/// it says to whom they went.
struct DadiPage: View {
    let store: WatchStore

    var body: some View {
        VStack(spacing: 12) {
            TextFieldLink(prompt: Text("Tell Dadi…")) {
                mark
            } onSubmit: { words in
                store.route(words)
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityLabel("Talk to Dadi")
            status
                .font(.footnote)
                .multilineTextAlignment(.center)
                .frame(minHeight: 34)
        }
        .animation(Motion.settle, value: store.handoff)
        .task(id: store.handoff) {
            guard case .sent = store.handoff else { return }
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            store.settle()
        }
    }

    private var busy: Bool { store.handoff == .sending || store.handoff == .routing }

    private var mark: some View {
        ZStack {
            if busy {
                Circle()
                    .fill(.sage.opacity(0.35))
                    .frame(width: 92, height: 92)
                    .phaseAnimator([false, true]) { ring, out in
                        ring.scaleEffect(out ? 1.4 : 1).opacity(out ? 0 : 0.6)
                    } animation: { out in out ? .easeOut(duration: 2.4) : nil }
            }
            Circle()
                .fill(LinearGradient(colors: [.sage, .sageDeep], startPoint: .top, endPoint: .bottom))
                .frame(width: 92, height: 92)
            Text("દ")
                .font(.wordmark(50))
                .inkCentered(.letter, size: 50)
                .foregroundStyle(.white)
        }
        .frame(width: 128, height: 128)
    }

    @ViewBuilder
    private var status: some View {
        switch store.handoff {
        case .idle:
            Text("Tap to talk to Dadi").foregroundStyle(.secondary)
        case .sending, .routing:
            HStack(spacing: 6) {
                ThinkingMark()
                Text("routing").foregroundStyle(.sage)
            }
        case .sent(let name):
            Label("Sent to \(name)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.sage)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.danger)
                .onTapGesture { store.settle() }
        }
    }
}
