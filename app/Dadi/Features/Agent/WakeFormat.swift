import Foundation

/// What the agent is doing this moment: the latest call of its running wake.
struct CurrentCall: Equatable, Sendable {
    let name: String
    let target: String
    /// True while the call has no result.
    let running: Bool
    /// When the turn that made the call happened.
    let at: Date
}

/// The entries of one clock minute.
struct MinuteGroup: Identifiable, Equatable {
    let clock: String
    var entries: [WakeEntry]

    var id: String { clock + String(entries.first?.ord ?? 0) }
}

extension WakeEntry {
    /// When the entry happened.
    var at: Date {
        switch self {
        case .message(let entry): entry.at
        case .turn(let turn): turn.at
        }
    }
}

/// The words the wake rows and entries use, and what they derive from a wake.
enum WakeFormat {
    /// The words of a wake outcome.
    static func label(_ outcome: WakeOutcome) -> String {
        switch outcome {
        case .running: "Running"
        case .waiting: "Waiting"
        case .yielded: "Yielded"
        case .failed: "Failed"
        }
    }

    /// The reason a wake began as a sentence and the agent it names: a `message` wake names its sender (no sender is
    /// Ankur), a `schedule` wake the routine or reminder when the sheet still knows it.
    static func reason(_ reason: WakeReason, routines: Routines?, nameOf: (String) -> String) -> (lead: String, name: String?, agentId: String?) {
        switch reason.kind {
        case .message: ("Opened by", reason.ref.map(nameOf) ?? "Ankur", reason.ref)
        case .schedule:
            if let routine = routines?.routines.first(where: { $0.id == reason.ref }) { ("Routine", routine.title, nil) }
            else if let reminder = routines?.reminders.first(where: { $0.id == reason.ref }) { ("Reminder", reminder.note, nil) }
            else { ("Routine or reminder", nil, nil) }
        case .recovery: ("Recovery", nil, nil)
        case .steer: ("Helper reported back", nil, nil)
        case .manual: ("Started by hand", nil, nil)
        }
    }

    /// The reason as one string: "Opened by Ankur", "Routine Morning triage", "Recovery".
    static func reasonText(_ reason: WakeReason, routines: Routines?, nameOf: (String) -> String) -> String {
        let line = Self.reason(reason, routines: routines, nameOf: nameOf)
        return [line.lead, line.name].compactMap { $0 }.joined(separator: " ")
    }

    /// A count of thousands as `1.2k`, of millions as `3.4M`, below that the number.
    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        return n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : String(n)
    }

    /// A wake's counts as one line, leaving out what is zero; empty when it did nothing: "6 tool calls · 1 message sent".
    static func counts(_ counts: WakeCounts) -> String {
        [
            counts.toolCalls > 0 ? "\(counts.toolCalls) tool \(counts.toolCalls == 1 ? "call" : "calls")" : nil,
            counts.messagesSent > 0 ? "\(counts.messagesSent) \(counts.messagesSent == 1 ? "message" : "messages") sent" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    /// A wake's second line: when it began, how long it ran, and what it did. "4 minutes ago · ran 2m · 6 tool calls · 1 message sent".
    static func facts(_ wake: WakeSummary, now: Date) -> String {
        let counts = counts(wake.counts)
        return [
            AgentTime.ago(wake.startedAt, now: now),
            wake.endedAt == nil ? "running for \(duration(wake, now: now))" : "ran \(duration(wake, now: now))",
            counts.isEmpty ? nil : counts,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    /// The entries in runs that share a minute, each run with the one clock time it is drawn under.
    static func inMinutes(_ entries: [WakeEntry]) -> [MinuteGroup] {
        var groups: [MinuteGroup] = []
        for entry in entries {
            let clock = AgentTime.clock(entry.at)
            if let last = groups.last, last.clock == clock {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append(MinuteGroup(clock: clock, entries: [entry]))
            }
        }
        return groups
    }

    /// A duration at the coarsest unit that still says something: "12s", "3m", "1h 5m".
    static func span(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        if total < 60 { return "\(total)s" }
        let minutes = Int((Double(total) / 60).rounded())
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// How long a wake took, or has taken as of `now` when it still runs.
    static func duration(_ wake: WakeSummary, now: Date) -> String {
        span((wake.endedAt ?? now).timeIntervalSince(wake.startedAt))
    }

    /// Input keys that name what a tool call acts on, most telling first.
    private static let targetKeys = ["url", "path", "file_path", "id", "to", "to_agent_id", "query", "command", "name", "instruction", "message", "content"]

    /// The longest a call's target is drawn before it is cut, in characters.
    private static let targetMax = 72

    /// What a tool call acts on, read from its input: the first of the well-known keys with text, else the first text value by key, else empty.
    static func target(_ input: JSONValue) -> String {
        guard let fields = input.object else { return "" }
        let text = targetKeys.lazy.compactMap { fields[$0]?.string }.first { !$0.isEmpty }
            ?? fields.keys.sorted().lazy.compactMap { fields[$0]?.string }.first { !$0.isEmpty }
        guard let text else { return "" }
        let oneLine = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return oneLine.count > targetMax ? String(oneLine.prefix(targetMax - 1)) + "…" : oneLine
    }

    /// The last call of the latest turn that made one, in a running wake's entries; nil when it has not called anything.
    static func currentCall(_ entries: [WakeEntry]) -> CurrentCall? {
        for entry in entries.reversed() {
            guard case .turn(let turn) = entry, let call = turn.calls.last else { continue }
            return CurrentCall(name: call.name, target: target(call.input), running: call.result == nil, at: turn.at)
        }
        return nil
    }

    /// The plain sentence for a halt that Hath refused, by its error code or status; Hath's own words for any other.
    static func haltSentence(_ error: Error) -> String {
        guard let service = error as? ServiceError else { return error.localizedDescription }
        switch (service.type, service.status) {
        case ("task_not_found", _): return "That task no longer exists."
        case ("task_conflict", _): return "The task changed while stopping it; try again."
        case (_, 502): return "Nas did not answer, so the task was not stopped."
        default: return service.message
        }
    }

    /// A tool input as display text: objects and arrays indented with sorted keys, a string as it is.
    static func pretty(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): return pretty(text: text)
        case .null: return "null"
        case .bool(let flag): return String(flag)
        case .number(let number): return number.rounded() == number ? String(Int(number)) : String(number)
        case .array, .object: return indented(value.foundation) ?? ""
        }
    }

    /// Tool result text as display text: JSON text indented, any other text as it is. A result cut at the server cap may be unfinished JSON; it is shown as received.
    static func pretty(text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)),
              let formatted = indented(object) else { return text }
        return formatted
    }

    /// The text of a raw `tool_result` log row: its `content` when it has text, else the whole payload as JSON.
    static func rawContent(_ log: LogRecord) -> String {
        if let content = log.payload["content"]?.string { return content }
        return indented(JSONValue.object(log.payload).foundation) ?? ""
    }

    private static func indented(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

private extension JSONValue {
    /// The value as a Foundation object for JSONSerialization.
    var foundation: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .number(let value): value
        case .string(let value): value
        case .array(let values): values.map(\.foundation)
        case .object(let fields): fields.mapValues(\.foundation)
        }
    }
}
