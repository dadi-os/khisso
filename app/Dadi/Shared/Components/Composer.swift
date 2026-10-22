import SwiftUI

/// The message field and its send button, two shapes of one liquid glass:
/// once there is something to send, the button flows out of the field's end
/// on one spring and the field draws in to make room, and it flows back in
/// when the field empties. The glass only melds while the shapes move: at rest
/// the gap between them is wider than the container's merge distance, so no
/// bridge of glass is left between them. Sending puts the keyboard away. The
/// field's rim answers the agent's lanes as thaali's does: quieter while it
/// thinks, sage while it works.
struct Composer: View {
    @Binding var text: String
    let placeholder: String
    /// A send is in flight: the button spins and another send waits.
    let busy: Bool
    var lanes: Set<Lane> = []
    let send: () -> Void

    @Namespace private var glass
    @FocusState private var focused: Bool

    /// The gap between field and button at rest, wider than `merge`.
    private let gap: CGFloat = 10
    /// How near the two shapes must be for their glass to meld.
    private let merge: CGFloat = 6

    private var rim: Color {
        if lanes.contains(.conversation) { return .sageLine.opacity(0.28) }
        if lanes.contains(.reasoning) { return .sage.opacity(0.36) }
        return .sageLine.opacity(0.42)
    }

    private var ready: Bool { !busy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The button is out while there is something to send or a send is in flight.
    private var showsSend: Bool { ready || busy }

    var body: some View {
        GlassEffectContainer(spacing: merge) {
            HStack(alignment: .bottom, spacing: gap) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .focused($focused)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .onSubmit(submit)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 23, style: .continuous))
                    .glassEffectID("field", in: glass)
                    .overlay {
                        RoundedRectangle(cornerRadius: 23, style: .continuous)
                            .strokeBorder(rim, lineWidth: 1)
                            .animation(Motion.settle, value: lanes)
                    }
                if showsSend {
                    Button(action: submit) {
                        ZStack {
                            if busy {
                                ProgressView().controlSize(.small).tint(.bone)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.bone)
                            }
                        }
                        .frame(width: 46, height: 46)
                        .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.sageDeep).interactive(), in: .circle)
                    .glassEffectID("send", in: glass)
                    .disabled(!ready)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Send")
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: showsSend)
        .frame(maxWidth: 680)
    }

    /// Lets the keyboard down, then sends.
    private func submit() {
        guard ready else { return }
        focused = false
        send()
    }
}
