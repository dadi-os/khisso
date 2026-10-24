import Foundation

/// A tool call's logged result.
struct ToolOutcome: Sendable, Hashable {
    let content: String
    let isError: Bool
}

/// One tool call, paired with its `tool_result` row by tool_use_id.
struct ActivityTool: Sendable, Hashable {
    let id: String
    let name: String
    let input: [String: JSONValue]
    /// Nil until the tool's result is logged.
    let result: ToolOutcome?

    /// The call as `name(key: value, …)`, its first three arguments by name.
    var signature: String {
        let keys = input.keys.sorted()
        guard !keys.isEmpty else { return "\(name)()" }
        let shown = keys.prefix(3).map { "\($0): \(Self.brief(input[$0] ?? .null))" }
        let raw = "\(name)(\(shown.joined(separator: ", "))\(keys.count > 3 ? ", …" : ""))"
        return raw.count <= 64 ? raw : String(raw.prefix(63)) + "…"
    }

    private static func brief(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let value): return String(value)
        case .number(let value): return value.rounded() == value ? String(Int(value)) : String(value)
        case .string(let value):
            let trimmed = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return "\"" + (trimmed.count <= 22 ? trimmed : String(trimmed.prefix(21)) + "…") + "\""
        case .array, .object: return "…"
        }
    }
}

/// What a model call wrote or called, in the order it produced them.
enum TurnPart: Sendable, Hashable, Identifiable {
    case text(key: String, String)
    case tool(key: String, ActivityTool)

    var id: String {
        switch self {
        case .text(let key, _), .tool(let key, _): key
        }
    }
}

/// One model call that wrote something or called a shown tool.
struct TurnStep: Sendable, Hashable {
    let key: String
    let lane: Lane
    let at: Date
    /// The call's thinking, joined; nil when it had none.
    let thought: String?
    let parts: [TurnPart]

    /// One line that stands for the thought: its first bold heading, else its first line.
    var gist: String? {
        guard let thought else { return nil }
        if let range = thought.range(of: #"(?m)^\s*\*\*(.+?)\*\*\s*$"#, options: .regularExpression) {
            return thought[range].trimmingCharacters(in: CharacterSet(charactersIn: "* \n\t"))
        }
        let first = thought.drop(while: \.isWhitespace).prefix { !$0.isNewline }
        return first.filter { !"*_`#>".contains($0) }.trimmingCharacters(in: .whitespaces)
    }
}

/// A message this agent received or sent.
struct MessageStep: Sendable, Hashable {
    enum Direction: Sendable { case receive, send }

    let key: String
    let lane: Lane
    let at: Date
    let direction: Direction
    /// The other side: an agent id, or nil for Ankur.
    let peer: String?
    /// True when Hath's scheduler delivered it.
    let scheduled: Bool
    /// True for the runtime's report that this agent's wake stopped.
    let wakeStopped: Bool
    let content: String
}

/// One entry on a wake's timeline.
enum ActivityStep: Sendable, Hashable, Identifiable {
    case turn(TurnStep)
    case message(MessageStep)

    var id: String { key }

    var key: String {
        switch self {
        case .turn(let step): step.key
        case .message(let step): step.key
        }
    }

    var lane: Lane {
        switch self {
        case .turn(let step): step.lane
        case .message(let step): step.lane
        }
    }
}

/// One stretch of work, its steps oldest first.
struct ActivityWake: Sendable, Hashable, Identifiable {
    var key: String
    let startedAt: Date
    var at: Date
    var steps: [ActivityStep] = []
    /// Lanes that took a model turn in this wake.
    var lanes: [Lane] = []
    /// Tool calls made, yield excluded.
    var toolCount = 0
    /// Tool calls whose logged result is an error.
    var errorCount = 0

    var id: String { key }
}

/// Shapes an agent's durable logs into wakes, as thaali's activity feed does:
/// a wake is one stretch of work from a received message (or a lane starting
/// cold) until both lanes have yielded. Hath stamps every row a wake writes
/// with its `wake_id`; only rows from before wake ids are grouped by guessing
/// from lane state and gaps.
enum Activity {
    /// Longest quiet stretch inside one guessed wake.
    private static let wakeGap: TimeInterval = 10 * 60

    /// How Hath's reports that work stopped opened before they became notices.
    private static let runtimeReportPrefix = "[runtime] "

    /// Tools that handed work to the other lane in rows without a wake id.
    private static let handoff: [String: Lane] = [
        "steer_reasoning": .reasoning,
        "send_message": .conversation,
        "hand_off": .conversation,
    ]

    /// `logs` (any order) as wakes, newest first, each with its steps oldest
    /// first. Wakes with nothing to show are dropped.
    static func wakes(from logs: [LogRecord]) -> [ActivityWake] {
        let results = outcomes(in: logs)
        let chronological = logs.sorted { $0.createdAt < $1.createdAt }
        var byId: [String: Int] = [:]
        var stamped: [ActivityWake] = []
        var unstamped: [LogRecord] = []
        for log in chronological {
            guard let wakeId = log.wakeId else {
                unstamped.append(log)
                continue
            }
            if log.event == .toolResult { continue }
            let index: Int
            if let known = byId[wakeId] {
                index = known
            } else {
                index = stamped.count
                byId[wakeId] = index
                stamped.append(ActivityWake(key: log.id, startedAt: log.createdAt, at: log.createdAt))
            }
            if log.event == .message {
                addMessage(&stamped[index], log)
            } else {
                addTurn(&stamped[index], log, turn(log, results))
            }
        }
        return (stamped + guessWakes(unstamped, results))
            .filter { !$0.steps.isEmpty }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// Gives each wake in `next` the key of the `previous` wake it shares a
    /// step with, so a wake keeps its identity (and its open state) when the
    /// log window slides past the row it started on.
    static func carryKeys(from previous: [ActivityWake], to next: [ActivityWake]) -> [ActivityWake] {
        var keyByStep: [String: String] = [:]
        for wake in previous {
            for step in wake.steps { keyByStep[step.key] = wake.key }
        }
        var taken = Set(next.map(\.key))
        return next.map { wake in
            guard let carried = wake.steps.compactMap({ keyByStep[$0.key] }).first(where: { $0 != wake.key && !taken.contains($0) }) else {
                return wake
            }
            taken.insert(carried)
            var carriedWake = wake
            carriedWake.key = carried
            return carriedWake
        }
    }

    private struct ParsedTurn {
        /// Nil when the call wrote nothing and called only hidden tools.
        let step: TurnStep?
        let tools: [ActivityTool]
        /// True when the lane stopped after this call.
        let ends: Bool
    }

    private static func outcomes(in logs: [LogRecord]) -> [String: ToolOutcome] {
        var results: [String: ToolOutcome] = [:]
        for log in logs where log.event == .toolResult {
            guard let id = log.payload["tool_use_id"]?.string, let content = log.payload["content"]?.string else { continue }
            results[id] = ToolOutcome(content: content, isError: log.payload["is_error"]?.bool == true)
        }
        return results
    }

    /// Whether a tool call is left off the timeline: yield ends every lane
    /// turn, and a delivered message already shows as its own sent message.
    /// Failures always show.
    private static func isHidden(_ tool: ActivityTool) -> Bool {
        if tool.result?.isError == true { return false }
        if tool.name == "send_message" {
            return tool.result.map { !$0.content.contains(#""handed_off":true"#) } ?? false
        }
        return tool.name == "yield" || tool.name == "dispatch_message"
    }

    private static func turn(_ log: LogRecord, _ results: [String: ToolOutcome]) -> ParsedTurn {
        var thoughts: [String] = []
        var parts: [TurnPart] = []
        var tools: [ActivityTool] = []
        for (index, raw) in (log.payload["content"]?.array ?? []).enumerated() {
            guard let block = raw.object else { continue }
            let key = "\(log.id):\(index)"
            switch block["type"]?.string {
            case "thinking":
                if let text = block["thinking"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    thoughts.append(text)
                }
            case "text":
                if let text = block["text"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    parts.append(.text(key: key, text))
                }
            case "tool_use":
                guard let id = block["id"]?.string, let name = block["name"]?.string else { continue }
                let tool = ActivityTool(id: id, name: name, input: block["input"]?.object ?? [:], result: results[id])
                tools.append(tool)
                if !isHidden(tool) { parts.append(.tool(key: key, tool)) }
            default:
                continue
            }
        }
        let ends = log.payload["stop_reason"]?.string != "tool_use" || tools.contains { $0.name == "yield" }
        guard !parts.isEmpty else { return ParsedTurn(step: nil, tools: tools, ends: ends) }
        let thought = thoughts.joined(separator: "\n\n")
        return ParsedTurn(
            step: TurnStep(key: log.id, lane: log.lane, at: log.createdAt, thought: thought.isEmpty ? nil : thought, parts: parts),
            tools: tools,
            ends: ends
        )
    }

    private static func message(_ log: LogRecord) -> MessageStep? {
        guard let content = log.payload["content"]?.string,
              let raw = log.payload["direction"]?.string,
              let direction = raw == "receive" ? MessageStep.Direction.receive : raw == "send" ? .send : nil
        else { return nil }
        let peer = log.payload[direction == .receive ? "from_agent_id" : "to_agent_id"]?.string
        return MessageStep(
            key: log.id,
            lane: log.lane,
            at: log.createdAt,
            direction: direction,
            peer: peer,
            scheduled: log.payload["schedule_id"]?.string != nil,
            wakeStopped: direction == .send && (log.payload["kind"]?.string == "notice" || content.hasPrefix(runtimeReportPrefix)),
            content: content
        )
    }

    private static func addTurn(_ wake: inout ActivityWake, _ log: LogRecord, _ turn: ParsedTurn) {
        if !wake.lanes.contains(log.lane) { wake.lanes.append(log.lane) }
        for tool in turn.tools {
            if tool.name != "yield" { wake.toolCount += 1 }
            if tool.result?.isError == true { wake.errorCount += 1 }
        }
        if let step = turn.step {
            wake.steps.append(.turn(step))
            wake.at = step.at
        }
    }

    @discardableResult
    private static func addMessage(_ wake: inout ActivityWake, _ log: LogRecord) -> MessageStep? {
        guard let step = message(log) else { return nil }
        wake.steps.append(.message(step))
        wake.at = step.at
        return step
    }

    /// Groups rows without a wake id (oldest first) into wakes: a received
    /// message or a model call starts a new wake when both lanes are idle, and
    /// a handoff leaves its target lane pending so the turn it causes joins
    /// the same wake.
    private static func guessWakes(_ chronological: [LogRecord], _ results: [String: ToolOutcome]) -> [ActivityWake] {
        var wakes: [ActivityWake] = []
        var busy: [Lane: Bool] = [.conversation: false, .reasoning: false]
        var pending = busy
        var lastAt: Date?

        for log in chronological where log.event != .toolResult {
            let opens = (log.event == .response && pending[log.lane] != true) || log.payload["direction"]?.string == "receive"
            let idle = busy.values.allSatisfy { !$0 }
            if wakes.isEmpty || log.createdAt.timeIntervalSince(lastAt ?? log.createdAt) > wakeGap || (opens && idle) {
                wakes.append(ActivityWake(key: log.id, startedAt: log.createdAt, at: log.createdAt))
                busy = [.conversation: false, .reasoning: false]
                pending = busy
            }
            lastAt = log.createdAt
            let last = wakes.count - 1

            if log.event == .message {
                let step = addMessage(&wakes[last], log)
                if log.payload["direction"]?.string == "receive" { busy[.conversation] = true }
                if step?.wakeStopped == true {
                    busy = [.conversation: false, .reasoning: false]
                    pending = busy
                }
                continue
            }

            let parsed = turn(log, results)
            busy[log.lane] = !parsed.ends
            pending[log.lane] = false
            for tool in parsed.tools {
                if let target = handoff[tool.name], tool.result?.isError != true, busy[target] != true {
                    pending[target] = true
                }
            }
            addTurn(&wakes[last], log, parsed)
        }
        return wakes
    }
}
