import Foundation

/// The lane filter of an open wake: both lanes, or one.
enum LaneFilter: String, CaseIterable, Sendable {
    case all = "All"
    case work = "Work"
    case process = "Process"

    /// The entries an open wake shows under this filter: every message, and the turns of the chosen lane (every turn for All).
    func apply(to entries: [WakeEntry]) -> [WakeEntry] {
        let lane: Lane
        switch self {
        case .all: return entries
        case .work: lane = .work
        case .process: lane = .process
        }
        return entries.filter {
            if case .turn(let turn) = $0 { turn.lane == lane } else { true }
        }
    }
}

/// What the agent is doing this moment: its work lane's latest call.
struct CurrentCall: Equatable, Sendable {
    let name: String
    let target: String
    /// True while the call has no result.
    let running: Bool
    /// When the turn that made the call happened.
    let at: Date
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

    /// The reason a wake began as a sentence. A message wake names its sender, and no sender is Ankur.
    static func reason(_ reason: WakeReason, nameOf: (String) -> String) -> String {
        switch reason.kind {
        case .message: "Opened by \(reason.ref.map(nameOf) ?? "Ankur")"
        case .schedule: "Schedule"
        case .recovery: "Recovery"
        case .steer: "Steer"
        case .manual: "Manual"
        }
    }

    /// A count of thousands as `1.2k`, of millions as `3.4M`, below that the number.
    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        return n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : String(n)
    }

    /// A wake's usage as its chip says it: tokens read and written, and how many of the prompt came from cache.
    static func usage(_ usage: WakeUsage) -> String {
        "\(compact(usage.inputTokens + usage.outputTokens)) tok · \(compact(usage.cacheRead)) cached"
    }

    /// A wake's counts as one line, leaving out what is zero; empty when it did nothing.
    static func counts(_ counts: WakeCounts) -> String {
        [
            counts.toolCalls > 0 ? "\(counts.toolCalls) tool \(counts.toolCalls == 1 ? "call" : "calls")" : nil,
            counts.messagesReceived > 0 ? "\(counts.messagesReceived) in" : nil,
            counts.messagesSent > 0 ? "\(counts.messagesSent) out" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
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

    /// The last call of the work lane's latest turn that made one, in a running wake's entries; nil when the lane has not called anything.
    static func currentCall(_ entries: [WakeEntry]) -> CurrentCall? {
        for entry in entries.reversed() {
            guard case .turn(let turn) = entry, turn.lane == .work, let call = turn.calls.last else { continue }
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
