import SwiftUI

/// The message field and its send button, two shapes of one liquid glass:
/// once there is something to send, the button flows out of the field's end
/// on one spring and the field draws in to make room, and it flows back in
/// when the field empties. The field's rim answers the agent's lanes as
/// thaali's does: quieter while it thinks, sage while it works.
struct Composer: View {
    @Binding var text: String
    let placeholder: String
    /// Disables the field while a send is in flight.
    let busy: Bool
    var lanes: Set<Lane> = []
    let send: () -> Void

    @Namespace private var glass

    private var rim: Color {
        if lanes.contains(.conversation) { return .sageLine.opacity(0.28) }
        if lanes.contains(.reasoning) { return .sage.opacity(0.36) }
        return .sageLine.opacity(0.42)
    }

    private var ready: Bool { !busy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The button is out while there is something to send or a send is in flight.
    private var showsSend: Bool { ready || busy }

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .disabled(busy)
                    .onSubmit { if ready { send() } }
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 23, style: .continuous))
                    .glassEffectID("field", in: glass)
                    .overlay {
                        RoundedRectangle(cornerRadius: 23, style: .continuous)
                            .strokeBorder(rim, lineWidth: 1)
                            .animation(Motion.settle, value: lanes)
                    }
                if showsSend {
                    Button(action: send) {
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
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: showsSend)
        .frame(maxWidth: 680)
    }
}
