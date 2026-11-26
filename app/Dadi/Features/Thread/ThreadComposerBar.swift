import SwiftUI

/// A thread's one composer: attach, the field and send once there is something to send. It is shown
/// in the tab bar's accessory until the person starts typing, then above the keyboard, and both
/// read and write the thread's `ThreadDraft`, so words, photos and the quote carry across.
struct ThreadComposerBar: View {
    /// Where the composer sits.
    enum Placement {
        /// In the tab bar's accessory, whose glass it borrows; the field is a tap target that starts typing.
        case accessory
        /// Above the keyboard on its own glass, with the live field.
        case keyboard
    }

    let name: String
    let draft: ThreadDraft
    let placement: Placement
    /// Sends the draft to the agent.
    let send: () -> Void

    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement
    @FocusState private var focused: Bool

    private var condensed: Bool { placement == .accessory && accessoryPlacement == .inline }
    private var prompt: String { "Message \(name)\u{2026}" }

    var body: some View {
        HStack(spacing: 6) {
            if !condensed {
                AttachButton(choose: attach)
            }
            field
            if draft.canSend || draft.sending {
                sendButton
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, placement == .keyboard ? 4 : 0)
        .frame(maxWidth: .infinity, minHeight: 44)
        .modifier(KeyboardGlass(on: placement == .keyboard))
    }

    @ViewBuilder
    private var field: some View {
        @Bindable var draft = draft
        switch placement {
        case .accessory:
            Button { draft.editing = true } label: {
                Text(draft.text.isEmpty ? prompt : draft.text)
                    .foregroundStyle(draft.text.isEmpty ? Color.inkMuted : .ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, condensed ? 8 : 4)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(prompt)
        case .keyboard:
            TextField(prompt, text: $draft.text, axis: .vertical)
                .focused($focused)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .foregroundStyle(.ink)
                .padding(.horizontal, 4)
                .onSubmit(submit)
                .onAppear { focused = true }
                .onChange(of: focused) { _, now in
                    if !now { draft.editing = false }
                }
        }
    }

    private var sendButton: some View {
        Button(action: submit) {
            ZStack {
                if draft.sending {
                    ProgressView().controlSize(.small).tint(.bone)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.bone)
                }
            }
            .frame(width: 34, height: 34)
            .background(.sageDeep, in: .circle)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!draft.canSend)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel("Send")
    }

    /// Sends, and puts the keyboard away so the composer returns to the dock.
    private func submit() {
        guard draft.canSend else { return }
        send()
        draft.editing = false
    }

    /// Opens a photo source, which puts the keyboard away first: nobody types and shoots at once.
    private func attach(_ source: ThreadAttach) {
        draft.editing = false
        draft.attaching = source
    }
}

/// The glass the composer floats on above the keyboard; in the accessory the tab bar supplies it.
private struct KeyboardGlass: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24, style: .continuous))
        } else {
            content
        }
    }
}

/// The round plus that offers Camera or Photos: a plain 36 pt circle with a soft fill, no glass of
/// its own, so it reads the same in the accessory, condensed or expanded, and above the keyboard.
struct AttachButton: View {
    /// Called with the source the person chose.
    let choose: (ThreadAttach) -> Void

    var body: some View {
        Menu {
            Button { choose(.camera) } label: { Label("Camera", systemImage: "camera") }
            Button { choose(.library) } label: { Label("Photos", systemImage: "photo.on.rectangle") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.inkMuted)
                .frame(width: 36, height: 36)
                .background(.ink.opacity(0.06), in: .circle)
                .contentShape(.circle)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Add a photo")
    }
}
