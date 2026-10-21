import SwiftUI

/// The message field: one glass capsule with the send button in a fixed slot
/// at its end, so nothing moves as you type. The button waits faint until
/// there is something to send, then fills sage. Its rim answers the agent's
/// lanes as thaali's does: quieter while it thinks, sage while it works.
struct Composer: View {
    @Binding var text: String
    let placeholder: String
    /// Disables the field while a send is in flight.
    let busy: Bool
    var lanes: Set<Lane> = []
    let send: () -> Void

    private var rim: Color {
        if lanes.contains(.conversation) { return .sageLine.opacity(0.28) }
        if lanes.contains(.reasoning) { return .sage.opacity(0.36) }
        return .sageLine.opacity(0.42)
    }

    private var ready: Bool { !busy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .foregroundStyle(.ink)
                .padding(.leading, 18)
                .padding(.vertical, 12)
                .disabled(busy)
                .onSubmit { if ready { send() } }
            Button(action: send) {
                ZStack {
                    Circle().fill(ready ? Color.sageDeep : .inkFaint.opacity(0.22))
                    if busy {
                        ProgressView().controlSize(.small).tint(.bone)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(ready ? Color.bone : .inkFaint)
                    }
                }
                .frame(width: 34, height: 34)
                .scaleEffect(ready ? 1 : 0.9)
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            .keyboardShortcut(.return, modifiers: .command)
            .padding(.trailing, 6)
            .padding(.bottom, 6)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: ready)
            .accessibilityLabel("Send")
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(rim, lineWidth: 1)
                .animation(Motion.settle, value: lanes)
        }
        .frame(maxWidth: 680)
    }
}
