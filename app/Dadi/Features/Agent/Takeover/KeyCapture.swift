import SwiftUI
import UIKit

/// The sticky Ctrl of the keyboard's accessory row: armed, the next letter typed goes as a Ctrl chord.
@MainActor @Observable
final class TerminalModifiers {
    var ctrl = false
}

/// The row above the keyboard that iOS keyboards lack the keys for: Esc, Tab, a sticky Ctrl, the arrows and
/// Ctrl-C. It is part of the keyboard, not a second place to type.
private struct TerminalAccessory: View {
    let modifiers: TerminalModifiers
    let press: (KeyFields) -> Void

    var body: some View {
        HStack(spacing: 6) {
            key("esc") { press(KeyFields(key: "Escape")) }
            key("tab") { press(KeyFields(key: "Tab")) }
            key("ctrl", on: modifiers.ctrl) { modifiers.ctrl.toggle() }
            key("\u{2190}") { press(KeyFields(key: "ArrowLeft")) }
            key("\u{2191}") { press(KeyFields(key: "ArrowUp")) }
            key("\u{2193}") { press(KeyFields(key: "ArrowDown")) }
            key("\u{2192}") { press(KeyFields(key: "ArrowRight")) }
            key("^C") { press(KeyFields(key: "c", ctrl: true)) }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }

    private func key(_ label: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.callout.monospaced().weight(.semibold))
                .foregroundStyle(.ink)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(.sage.opacity(on ? 0.4 : 0.16), in: .rect(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label == "ctrl" ? "Control, sticky" : label)
    }
}

/// A view that takes the keyboard and turns what is typed into key presses: printable text, Return,
/// Delete, and from a hardware keyboard the arrows, Esc, Tab and Ctrl chords.
@MainActor
final class KeyCaptureView: UIView, UIKeyInput {
    var onKey: (KeyFields) -> Void = { _ in }
    private let modifiers: TerminalModifiers
    private var wasActive = false
    private var lastRefocus = 0
    private var accessory: UIInputView?
    private var hosting: UIHostingController<TerminalAccessory>?

    var autocorrectionType = UITextAutocorrectionType.no
    var autocapitalizationType = UITextAutocapitalizationType.none
    var spellCheckingType = UITextSpellCheckingType.no
    var smartQuotesType = UITextSmartQuotesType.no
    var smartDashesType = UITextSmartDashesType.no
    var smartInsertDeleteType = UITextSmartInsertDeleteType.no
    var keyboardType = UIKeyboardType.asciiCapable

    init(modifiers: TerminalModifiers) {
        self.modifiers = modifiers
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { true }

    override var inputAccessoryView: UIView? {
        if let accessory { return accessory }
        let hosting = UIHostingController(rootView: TerminalAccessory(modifiers: modifiers) { [weak self] fields in self?.onKey(fields) })
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        let bar = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
        bar.allowsSelfSizing = true
        bar.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: bar.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])
        self.hosting = hosting
        accessory = bar
        return bar
    }

    /// Opens the keyboard when `active` turns on or `refocus` changes while it is on, and closes it when `active` turns off.
    func focus(active: Bool, refocus: Int) {
        defer { wasActive = active; lastRefocus = refocus }
        if active, !wasActive || refocus != lastRefocus {
            if window != nil { becomeFirstResponder() }
        } else if !active, isFirstResponder {
            resignFirstResponder()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, wasActive { becomeFirstResponder() }
    }

    func insertText(_ text: String) {
        for character in text {
            if character.isNewline {
                onKey(KeyFields(key: "Enter"))
                continue
            }
            let key = String(character)
            let chord = modifiers.ctrl
            modifiers.ctrl = false
            onKey(KeyFields(key: key, ctrl: chord))
        }
    }

    func deleteBackward() {
        onKey(KeyFields(key: "Backspace"))
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, let fields = Self.fields(of: key) else { continue }
            onKey(fields)
            handled.insert(press)
        }
        super.pressesBegan(presses.subtracting(handled), with: event)
    }

    /// A hardware key that does not arrive as text: the arrows, Esc, Tab, Home, End, paging, Delete and Ctrl with a letter.
    private static func fields(of key: UIKey) -> KeyFields? {
        let flags = key.modifierFlags
        let named: String? = switch key.keyCode {
        case .keyboardUpArrow: "ArrowUp"
        case .keyboardDownArrow: "ArrowDown"
        case .keyboardLeftArrow: "ArrowLeft"
        case .keyboardRightArrow: "ArrowRight"
        case .keyboardEscape: "Escape"
        case .keyboardTab: "Tab"
        case .keyboardHome: "Home"
        case .keyboardEnd: "End"
        case .keyboardPageUp: "PageUp"
        case .keyboardPageDown: "PageDown"
        case .keyboardDeleteForward: "Delete"
        default: nil
        }
        if let named { return KeyFields(key: named, ctrl: flags.contains(.control), alt: flags.contains(.alternate), shift: flags.contains(.shift)) }
        if flags.contains(.control), key.charactersIgnoringModifiers.count == 1 {
            return KeyFields(key: key.charactersIgnoringModifiers, ctrl: true)
        }
        return nil
    }
}

/// The keyboard bridge: while `active` its keys go to `onKey`, and tapping the pane again (`refocus` changes)
/// brings the keyboard back after it was dismissed.
struct KeyCapture: UIViewRepresentable {
    let active: Bool
    let refocus: Int
    let modifiers: TerminalModifiers
    let onKey: (KeyFields) -> Void

    func makeUIView(context: Context) -> KeyCaptureView {
        KeyCaptureView(modifiers: modifiers)
    }

    func updateUIView(_ view: KeyCaptureView, context: Context) {
        view.onKey = onKey
        view.focus(active: active, refocus: refocus)
    }
}
