import SwiftUI

/// A terminal you type into: the output pane is the only place to enter anything. While Ankur is in control
/// the keyboard opens over it (with Esc, Tab, Ctrl and the arrows above it), what he types goes to the
/// terminal in order, and the pane is read every 250 ms; while he watches it only shows the output, read
/// every second. Tapping the pane brings the keyboard back after it was dismissed.
struct TerminalPane: View {
    let nas: NasClient
    let terminalId: String
    let control: TakeoverControl

    /// Lines of the pane the sheet reads.
    private static let lines = 400

    @State private var sender: KeySender
    @State private var modifiers = TerminalModifiers()
    @State private var refocus = 0

    init(nas: NasClient, terminalId: String, control: TakeoverControl) {
        self.nas = nas
        self.terminalId = terminalId
        self.control = control
        _sender = State(initialValue: KeySender(
            send: { keys, literal in try await nas.terminalKeys(terminalId, keys: keys, literal: literal) },
            onError: { control.fail("The terminal did not take the keys", $0) }
        ))
    }

    private var controlling: Bool { control.state == .inControl }

    var body: some View {
        ScrollView {
            TaskTerminal(nas: nas, terminalId: terminalId, lines: Self.lines, fontSize: 12, poll: controlling ? .milliseconds(250) : .seconds(1))
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .contentShape(.rect)
        .onTapGesture { if controlling { refocus += 1 } }
        .background { KeyCapture(active: controlling, refocus: refocus, modifiers: modifiers, onKey: press).frame(width: 1, height: 1) }
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(controlling ? Color.sageDeep : .clear, lineWidth: 2) }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityLabel(controlling ? "Terminal, you are typing into it" : "Terminal output")
    }

    private func press(_ fields: KeyFields) {
        guard let input = terminalInput(of: fields), controlling else { return }
        if let activity = input.activity { _ = control.record(activity) }
        sender.push(input.batch)
    }
}
