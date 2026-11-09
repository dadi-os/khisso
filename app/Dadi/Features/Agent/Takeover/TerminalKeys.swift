import Foundation

/// Keys for POST /terminals/:id/keys: text as typed when `literal`, otherwise tmux key names such as `Enter` or `C-c`.
struct KeyBatch: Equatable, Sendable {
    var keys: [String]
    var literal: Bool
}

/// What a key press sends the pane, and what it counts as in the summary (nil for a key that only moves the cursor).
struct TerminalInput: Equatable, Sendable {
    let batch: KeyBatch
    let activity: TerminalActivity?
}

/// Named keys and the tmux name each sends.
private let namedKeys: [String: String] = [
    "Enter": "Enter",
    "Backspace": "BSpace",
    "Tab": "Tab",
    "Escape": "Escape",
    "ArrowUp": "Up",
    "ArrowDown": "Down",
    "ArrowLeft": "Left",
    "ArrowRight": "Right",
    "Home": "Home",
    "End": "End",
    "PageUp": "PPage",
    "PageDown": "NPage",
    "Delete": "DC",
]

/// The named keys that move the cursor or the view only, so the summary does not list them.
private let moveKeys: Set<String> = ["ArrowLeft", "ArrowRight", "Home", "End", "PageUp", "PageDown", "Delete"]

/// The input a key press makes in a terminal: a printable character as literal text, Enter, Backspace, Tab
/// (Shift-Tab as BTab), Escape, the arrows, Home, End, PageUp, PageDown and Delete as tmux names, and Ctrl with
/// a letter as `C-<letter>`. Nil for what is not the terminal's: chords holding Cmd, other Ctrl chords, and
/// modifiers alone.
func terminalInput(of fields: KeyFields) -> TerminalInput? {
    if fields.meta { return nil }
    if fields.ctrl {
        guard fields.key.count == 1, let scalar = fields.key.unicodeScalars.first, scalar.isASCII, scalar.properties.isAlphabetic else { return nil }
        return TerminalInput(batch: KeyBatch(keys: ["C-\(fields.key.lowercased())"], literal: false), activity: .key(keyName(fields)))
    }
    if fields.key.count == 1 {
        return TerminalInput(batch: KeyBatch(keys: [fields.key], literal: true), activity: .text(fields.key))
    }
    if fields.key == "Tab", fields.shift {
        return TerminalInput(batch: KeyBatch(keys: ["BTab"], literal: false), activity: .key("Shift-Tab"))
    }
    guard let named = namedKeys[fields.key] else { return nil }
    let activity: TerminalActivity? = fields.key == "Enter" ? .enter : fields.key == "Backspace" ? .backspace : moveKeys.contains(fields.key) ? nil : .key(keyName(fields))
    return TerminalInput(batch: KeyBatch(keys: [named], literal: false), activity: activity)
}

/// Text pasted into the pane, as the input it makes: literal, with its newlines. Nil for an empty paste.
func terminalPaste(of text: String) -> TerminalInput? {
    text.isEmpty ? nil : TerminalInput(batch: KeyBatch(keys: [text], literal: true), activity: .text(text))
}

/// Queue of keys for one terminal. `push` sends at once when idle, otherwise the batch waits and goes out with
/// everything queued behind the request in flight, with neighbouring batches of the same kind joined so fast
/// typing is a few requests. Order is kept. A failed request drops its batch and reports through `onError`;
/// there is no retry.
@MainActor
final class KeySender {
    private var queue: [KeyBatch] = []
    private var sending = false
    private let send: (_ keys: [String], _ literal: Bool) async throws -> Void
    private let onError: (any Error) -> Void

    init(send: @escaping (_ keys: [String], _ literal: Bool) async throws -> Void, onError: @escaping (any Error) -> Void) {
        self.send = send
        self.onError = onError
    }

    func push(_ batch: KeyBatch) {
        if let last = queue.last, last.literal == batch.literal {
            queue[queue.count - 1] = KeyBatch(keys: batch.literal ? [last.keys.joined() + batch.keys.joined()] : last.keys + batch.keys, literal: batch.literal)
        } else {
            queue.append(batch)
        }
        flush()
    }

    private func flush() {
        guard !sending, !queue.isEmpty else { return }
        let batches = queue
        queue = []
        sending = true
        Task {
            do {
                for batch in batches { try await send(batch.keys, batch.literal) }
            } catch {
                onError(error)
            }
            sending = false
            flush()
        }
    }
}
