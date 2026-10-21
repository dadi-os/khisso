import SwiftUI

/// The message field with its send button, in one glass container so they
/// morph together.
struct Composer: View {
    @Binding var text: String
    let placeholder: String
    /// Disables the field while a send is in flight.
    let busy: Bool
    let send: () -> Void

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 10) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassEffect(.regular, in: .capsule)
                    .onSubmit(send)
                    .disabled(busy)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy {
                    Button(action: send) {
                        Image(systemName: busy ? "ellipsis" : "arrow.up")
                            .font(.body.weight(.semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(busy)
                }
            }
            .animation(.snappy, value: text.isEmpty)
        }
        .frame(maxWidth: 680)
    }
}
