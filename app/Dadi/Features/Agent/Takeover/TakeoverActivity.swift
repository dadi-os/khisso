import Foundation

/// One thing Ankur did in a browser. A browser's summary holds counts only, never the text typed (it may be a
/// password or a code).
enum BrowserActivity: Equatable, Sendable {
    case click
    case scroll
    case type(chars: Int)
    /// A key or chord by name, such as `Enter` or `Ctrl-A`, or a navigation button (`Back`, `Reload`).
    case key(String)
}

/// One thing Ankur did in a terminal. A terminal's summary holds the commands he ran, which are the point of it.
enum TerminalActivity: Equatable, Sendable {
    case text(String)
    case enter
    case backspace
    /// A key or chord by name, such as `Ctrl-C` or `Up`.
    case key(String)
}

/// The fields of a key press that name it for a summary or choose what a terminal is sent.
struct KeyFields: Equatable, Sendable {
    /// The DOM name of the key: the character it types, or `Enter`, `Backspace`, `ArrowUp` and so on.
    var key: String
    var ctrl = false
    var alt = false
    var meta = false
    var shift = false
}

/// A key as the summaries name it: `Up` for ArrowUp, `Ctrl-C` for Ctrl and c, `Shift-Tab`; the text of a printable key is never named.
func keyName(_ fields: KeyFields) -> String {
    let key = fields.key
    let base = key.hasPrefix("Arrow") ? String(key.dropFirst(5)) : key == " " ? "Space" : key.count == 1 ? key.uppercased() : key
    let prefix = (fields.ctrl ? "Ctrl-" : "") + (fields.alt ? "Alt-" : "") + (fields.meta ? "Cmd-" : "") + (fields.shift && key.count > 1 ? "Shift-" : "")
    return prefix + base
}

private let modifierKeys: Set<String> = ["Shift", "Control", "Alt", "Meta", "CapsLock"]

/// What a browser key press counts as: characters typed, a key or chord by name, or nil for a modifier on its own.
/// A character with Ctrl or Cmd held is a chord, named, not typed.
func browserKeyActivity(_ fields: KeyFields) -> BrowserActivity? {
    if modifierKeys.contains(fields.key) { return nil }
    if fields.key.count == 1, !fields.ctrl, !fields.meta { return .type(chars: 1) }
    return .key(keyName(fields))
}

/// A count as prose: once, twice, 3 times.
private func times(_ count: Int) -> String {
    count == 1 ? "once" : count == 2 ? "twice" : "\(count) times"
}

/// Items as one list: `a`, `a and b`, `a, b, and c`.
private func listOf(_ items: [String]) -> String {
    items.count < 3 ? items.joined(separator: " and ") : items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
}

/// The record of a browser takeover: clicks, whether he scrolled, the characters typed and the keys pressed by
/// name, in the order each key was first pressed. The summary omits what is zero, and says he did nothing when
/// it all is.
struct BrowserActivityLog: Sendable {
    private var clicks = 0
    private var scrolled = false
    private var typed = 0
    private var keys: [(name: String, count: Int)] = []

    mutating func record(_ event: BrowserActivity) {
        switch event {
        case .click: clicks += 1
        case .scroll: scrolled = true
        case .type(let chars): typed += chars
        case .key(let name):
            if let index = keys.firstIndex(where: { $0.name == name }) { keys[index].count += 1 } else { keys.append((name, 1)) }
        }
    }

    /// The summary of everything recorded since the last reset, as the helper is told it.
    func summary() -> String {
        var did: [String] = []
        if clicks > 0 { did.append("clicked \(times(clicks))") }
        if scrolled { did.append("scrolled") }
        if typed > 0 { did.append("typed \(typed) \(typed == 1 ? "character" : "characters")") }
        for key in keys { did.append("pressed \(key.name) \(times(key.count))") }
        return did.isEmpty ? "Ankur took over this browser but did nothing." : "Ankur took over this browser. He \(listOf(did))."
    }

    /// Forgets everything recorded: a takeover starts from nothing.
    mutating func reset() { self = BrowserActivityLog() }
}

/// The record of a terminal takeover: each line he typed and ran, split at Enter, with the keys he pressed by
/// name between them. Backspace edits the line being typed; Ctrl-C and Ctrl-U drop it. Text typed and not yet
/// run is reported as such. Keys that only move the cursor are not recorded.
struct TerminalActivityLog: Sendable {
    /// Longest command, in characters, the summary quotes in full.
    static let commandChars = 200
    /// Most commands and keys the summary lists before it counts the rest.
    static let listed = 30

    private enum Item: Sendable {
        case command(String)
        case key(String)
    }

    private var items: [Item] = []
    private var line = ""

    mutating func record(_ event: TerminalActivity) {
        switch event {
        case .text(let text):
            let normal = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            for character in normal {
                if character == "\n" { run() } else { line.append(character) }
            }
        case .enter: run()
        case .backspace: if !line.isEmpty { line.removeLast() }
        case .key(let name):
            items.append(.key(name))
            if name == "Ctrl-C" || name == "Ctrl-U" { line = "" }
        }
    }

    /// The summary of everything recorded since the last reset, as the helper is told it.
    func summary() -> String {
        var shown = items.prefix(Self.listed).map { item in
            switch item {
            case .command(let text): Self.quoted(text)
            case .key(let name): name
            }
        }
        if items.count > Self.listed { shown.append("and \(items.count - Self.listed) more") }
        let unrun = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = unrun.isEmpty ? nil : "typed \(Self.quoted(unrun)) without running it"
        if shown.isEmpty, pending == nil { return "Ankur took over this terminal but typed nothing." }
        let ran = shown.isEmpty ? "" : " and ran: \(shown.joined(separator: ", "))"
        guard let pending else { return "Ankur took over this terminal\(ran)." }
        return shown.isEmpty ? "Ankur took over this terminal and \(pending)." : "Ankur took over this terminal\(ran), then \(pending)."
    }

    /// Forgets everything recorded: a takeover starts from nothing.
    mutating func reset() { self = TerminalActivityLog() }

    private mutating func run() {
        let command = line.trimmingCharacters(in: .whitespacesAndNewlines)
        items.append(command.isEmpty ? .key("Enter") : .command(command))
        line = ""
    }

    /// A command as the summary quotes it: cut at `commandChars` characters.
    private static func quoted(_ command: String) -> String {
        command.count > commandChars ? "`\(command.prefix(commandChars))…`" : "`\(command)`"
    }
}
