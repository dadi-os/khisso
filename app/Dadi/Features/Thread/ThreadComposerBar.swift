import SwiftUI

/// A thread's own composer: attach, the field and send once there is something to send, on glass at the
/// foot of the thread's page. It reads and writes the thread's `ThreadDraft`, so words, files and the
/// quote are the agent's own. Its field rides the keyboard up and down with the page's safe area, and
/// resigning `focus` is all it takes to lower both together.
struct ThreadComposerBar: View {
    let name: String
    let draft: ThreadDraft
    /// Whether the field has the keyboard.
    var focus: FocusState<Bool>.Binding
    /// Sends the draft to the agent.
    let send: () -> Void

    private var prompt: String { "Message \(name)\u{2026}" }

    var body: some View {
        @Bindable var draft = draft
        HStack(spacing: 6) {
            AttachButton(choose: attach)
            TextField(prompt, text: $draft.text, axis: .vertical)
                .focused(focus)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .foregroundStyle(.ink)
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
                .onSubmit(submit)
            if draft.canSend || draft.sending {
                sendButton
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 44)
        .frostedBacking(.rect(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24, style: .continuous))
        .animation(Motion.snap, value: draft.canSend || draft.sending)
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

    /// Sends, and lowers the keyboard with the composer.
    private func submit() {
        guard draft.canSend else { return }
        send()
        focus.wrappedValue = false
    }

    private func attach(_ source: ThreadAttach) {
        draft.attaching = source
    }
}

/// The round plus that offers the sources: a plain 36 pt circle with a soft fill, no glass of
/// its own, in a native menu that leaves the keyboard up.
struct AttachButton: View {
    /// Called with the source the person chose.
    let choose: (ThreadAttach) -> Void

    var body: some View {
        AttachMenu(choose: choose) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.inkMuted)
                .frame(width: 36, height: 36)
                .background(.ink.opacity(0.06), in: .circle)
                .contentShape(.circle)
        }
    }
}
