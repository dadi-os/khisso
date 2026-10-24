import SwiftUI

/// Recent agent activity from durable logs, as thaali's popover shows it:
/// wakes, each stretch of work from the message (or cold start) that set it
/// off until both lanes yielded, its messages and model calls in order with
/// each call's thought, text and tool calls. Filtered by lane; the newest wake
/// opens when it first appears and stays as left.
struct ActivityFeed: View {
    let wakes: [ActivityWake]
    /// The agent's lanes running now; marks the newest wake live.
    let lanes: Set<Lane>
    let nameOf: (String) -> String

    private enum Filter: String, CaseIterable {
        case all
        case conversation = "thinking"
        case reasoning = "working"

        var lane: Lane? {
            switch self {
            case .all: nil
            case .conversation: .conversation
            case .reasoning: .reasoning
            }
        }
    }

    /// Wakes shown at first, and added per "show older".
    private static let page = 5

    @State private var filter = Filter.all
    @State private var limit = ActivityFeed.page
    @State private var opened: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Lane", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: filter) { limit = Self.page }

            let shown = wakes.compactMap { wake -> (ActivityWake, [ActivityStep])? in
                let steps = wake.steps.filter { filter.lane == nil || $0.lane == filter.lane }
                return steps.isEmpty ? nil : (wake, steps)
            }
            if shown.isEmpty {
                Text(filter == .all ? "No recent activity." : "No recent \(filter.rawValue).")
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
            }
            ForEach(Array(shown.prefix(limit).enumerated()), id: \.element.0.key) { index, entry in
                let live = index == 0 && wakes.first?.key == entry.0.key && !lanes.isEmpty
                WakeRow(
                    wake: entry.0,
                    steps: entry.1,
                    live: live,
                    open: opened[entry.0.key] ?? (index == 0),
                    nameOf: nameOf,
                    toggle: { opened[entry.0.key] = !(opened[entry.0.key] ?? (index == 0)) }
                )
            }
            if shown.count > limit || limit > Self.page {
                HStack(spacing: 16) {
                    if shown.count > limit {
                        Button("show \(min(shown.count - limit, Self.page)) older") { limit += Self.page }
                    }
                    if limit > Self.page {
                        Button("show fewer") { limit = Self.page }
                    }
                }
                .font(.footnote)
                .foregroundStyle(.sageDeep)
            }
        }
        .animation(Motion.settle, value: wakes)
    }
}

/// A lane's mark: a filled dot for thinking, a ring for working.
private struct LaneDot: View {
    let lane: Lane
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(lane == .conversation ? Color.sage : .bone)
            .overlay(Circle().strokeBorder(Color.sageDeep.opacity(lane == .conversation ? 0 : 0.7), lineWidth: 1.2))
            .frame(width: size, height: size)
    }
}

/// One wake: what set it off, which lanes worked, its tool calls, failures and
/// span. Open, its steps run oldest first down a rail; closed, its opening
/// step stands in as one line. A long wake folds its middle steps.
private struct WakeRow: View {
    let wake: ActivityWake
    let steps: [ActivityStep]
    let live: Bool
    let open: Bool
    let nameOf: (String) -> String
    let toggle: () -> Void

    /// A long wake shows its opening steps and its latest, folding the middle.
    private static let head = 2
    private static let tail = 8

    @State private var unfolded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(spacing: 3) {
                        ForEach(wake.lanes, id: \.self) { LaneDot(lane: $0, size: 7) }
                    }
                    .opacity(live ? 0.6 : 1)
                    Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.ink).lineLimit(1)
                    Text(meta).font(.caption).foregroundStyle(.inkFaint).lineLimit(1)
                    Spacer(minLength: 4)
                    if live {
                        Text("now").font(.caption2).foregroundStyle(.sageDeep)
                    } else {
                        Text(wake.at, format: .relative(presentation: .named, unitsStyle: .narrow))
                            .font(.caption2)
                            .foregroundStyle(.inkFaint)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if open {
                rail
            } else if let first = steps.first {
                Text(preview(first))
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private var title: String {
        if case .message(let first)? = steps.first, first.direction == .receive {
            let from = "from \(first.peer.map(nameOf) ?? "you")"
            return first.scheduled ? "scheduled \(from)" : from
        }
        return wake.lanes.map(\.label).joined(separator: " + ")
    }

    private var meta: String {
        let span = wake.at.timeIntervalSince(wake.startedAt)
        var parts: [String] = []
        if wake.toolCount > 0 { parts.append("\(wake.toolCount) tool call\(wake.toolCount == 1 ? "" : "s")") }
        if span >= 1 { parts.append(Self.span(span)) }
        if wake.errorCount > 0 { parts.append("\(wake.errorCount) failed") }
        return parts.joined(separator: " · ")
    }

    private func preview(_ step: ActivityStep) -> String {
        switch step {
        case .message(let message):
            return Agent.preview(message.content)
        case .turn(let turn):
            switch turn.parts[0] {
            case .text(_, let text): return Agent.preview(text)
            case .tool(_, let tool): return tool.signature
            }
        }
    }

    private enum Row: Identifiable {
        case step(ActivityStep, lane: Bool)
        case fold(Int)

        var id: String {
            switch self {
            case .step(let step, _): step.key
            case .fold: "fold"
            }
        }
    }

    private var rows: [Row] {
        let folded = unfolded || steps.count <= Self.head + Self.tail + 1 ? 0 : steps.count - Self.head - Self.tail
        let shown: [ActivityStep?] = folded > 0 ? Array(steps.prefix(Self.head)) + [nil] + Array(steps.suffix(Self.tail)) : steps
        var previous: ActivityStep?
        return shown.map { step in
            guard let step else {
                previous = nil
                return .fold(folded)
            }
            defer { previous = step }
            return .step(step, lane: previous?.lane != step.lane)
        }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                switch row {
                case .fold(let count):
                    Button("show \(count) earlier step\(count == 1 ? "" : "s")") { unfolded = true }
                        .font(.footnote)
                        .foregroundStyle(.sageDeep)
                case .step(let step, let lane):
                    HStack(alignment: .top, spacing: 10) {
                        LaneDot(lane: step.lane, size: 7).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 4) {
                            if lane {
                                Text(step.lane.label).font(.caption2).foregroundStyle(.inkFaint)
                            }
                            StepView(step: step, live: live, nameOf: nameOf)
                        }
                    }
                }
            }
        }
        .padding(.leading, 2)
        .transition(.opacity)
    }

    /// A duration at the coarsest unit that still says something: "12s", "3m", "1h 5m".
    static func span(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let minutes = Int((Double(total) / 60).rounded())
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

/// One timeline entry of a wake, by kind.
private struct StepView: View {
    let step: ActivityStep
    let live: Bool
    let nameOf: (String) -> String

    var body: some View {
        switch step {
        case .message(let message):
            MessageBubble(message: message, nameOf: nameOf)
        case .turn(let turn):
            VStack(alignment: .leading, spacing: 4) {
                if let gist = turn.gist, let thought = turn.thought {
                    ThoughtLine(gist: gist, thought: thought)
                }
                ForEach(turn.parts) { part in
                    switch part {
                    case .text(_, let text):
                        Clamped(lines: 5) { Text(InlineMarkdown.attributed(text)).font(.footnote).foregroundStyle(.inkMuted) }
                    case .tool(_, let tool):
                        ToolRow(tool: tool, live: live)
                    }
                }
            }
        }
    }
}

/// Caps tall content at `lines`, with a show all / show less toggle once it
/// is long enough to overflow.
private struct Clamped<Content: View>: View {
    let lines: Int
    @ViewBuilder let content: Content

    @State private var open = false
    @State private var overflows = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content
                .lineLimit(open ? nil : lines)
                .background {
                    content.lineLimit(nil).fixedSize(horizontal: false, vertical: true).hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full in
                            overflows = full > CGFloat(lines) * 17
                        }
                }
            if overflows {
                Button(open ? "show less" : "show all") { withAnimation(Motion.snap) { open.toggle() } }
                    .font(.caption)
                    .foregroundStyle(.sageDeep)
            }
        }
    }
}

/// The thinking behind a model call as one quiet italic line, its gist;
/// tapping it opens the whole thought beneath.
private struct ThoughtLine: View {
    let gist: String
    let thought: String

    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation(Motion.snap) { open.toggle() } } label: {
                Text(gist).font(.caption).italic().foregroundStyle(.inkFaint).lineLimit(open ? nil : 1).multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            if open {
                Clamped(lines: 16) { Text(InlineMarkdown.attributed(thought)).font(.caption).italic().foregroundStyle(.inkFaint) }
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) { Rectangle().fill(Color.sageLine.opacity(0.5)).frame(width: 1) }
            }
        }
    }
}

/// A tool call as its `name(args)` signature with its status, expanding to the
/// full parameters and result. While it runs the row is tinted.
private struct ToolRow: View {
    let tool: ActivityTool
    let live: Bool

    @State private var open = false

    var body: some View {
        let running = tool.result == nil && live
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(Motion.snap) { open.toggle() } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(tool.signature)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(tool.result?.isError == true ? Color.inkMuted : .ink)
                        .strikethrough(tool.result?.isError == true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if tool.result == nil {
                        Text(running ? "running…" : "no result").font(.caption2).foregroundStyle(running ? Color.sageDeep : .inkFaint)
                    } else if tool.result?.isError == true {
                        Text("error").font(.caption2).foregroundStyle(.danger)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tool.input.keys.sorted(), id: \.self) { key in
                        HStack(alignment: .top, spacing: 0) {
                            Text(key).font(.system(size: 10, design: .monospaced)).foregroundStyle(.inkFaint)
                                .padding(.horizontal, 6).padding(.vertical, 4)
                                .background(.ink.opacity(0.06))
                            Clamped(lines: 7) { Text(Self.pretty(tool.input[key] ?? .null)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.ink) }
                                .padding(.horizontal, 6).padding(.vertical, 4)
                        }
                        .background(.sage.opacity(0.1), in: .rect(cornerRadius: 4))
                    }
                    if let result = tool.result, !result.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Clamped(lines: 10) {
                            Text(Self.prettyResult(result.content))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(result.isError ? Color.danger : .inkMuted)
                        }
                    }
                }
                .padding(.leading, 8)
                .overlay(alignment: .leading) { Rectangle().fill(Color.sageLine.opacity(0.5)).frame(width: 1) }
            }
        }
        .padding(running ? 6 : 0)
        .background(running ? Color.sage.opacity(0.14) : .clear, in: .rect(cornerRadius: 8))
    }

    /// A parameter as display text: strings as-is, anything structured as indented JSON.
    private static func pretty(_ value: JSONValue) -> String {
        switch value {
        case .null: "null"
        case .bool(let value): String(value)
        case .number(let value): value.rounded() == value ? String(Int(value)) : String(value)
        case .string(let value): value
        case .array, .object: json(value)
        }
    }

    private static func json(_ value: JSONValue) -> String {
        func object(_ value: JSONValue) -> Any {
            switch value {
            case .null: NSNull()
            case .bool(let value): value
            case .number(let value): value
            case .string(let value): value
            case .array(let value): value.map(object)
            case .object(let value): value.mapValues(object)
            }
        }
        do {
            return String(decoding: try JSONSerialization.data(withJSONObject: object(value), options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]), as: UTF8.self)
        } catch {
            return error.localizedDescription
        }
    }

    /// A result indented for reading when it is JSON; any other text as logged.
    private static func prettyResult(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let value = try? ServiceJSON.verbatim.decode(JSONValue.self, from: Data(trimmed.utf8))
        else { return content }
        return json(value)
    }
}

/// A received message as a filled bubble, a sent one outlined, and the
/// runtime's report of a stopped wake in the error tone.
private struct MessageBubble: View {
    let message: MessageStep
    let nameOf: (String) -> String

    var body: some View {
        let peer = message.peer.map(nameOf) ?? "you"
        let label = message.direction == .receive ? "from \(peer)" : "to \(peer)"
        VStack(alignment: .leading, spacing: 2) {
            Text(message.wakeStopped ? "wake stopped · \(label)" : message.scheduled ? "scheduled · \(label)" : label)
                .font(.caption2)
                .foregroundStyle(message.wakeStopped ? Color.danger : .inkFaint)
            Clamped(lines: 4) { Text(InlineMarkdown.attributed(message.content)).font(.footnote).foregroundStyle(.ink) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.wakeStopped ? Color.danger.opacity(0.1) : message.direction == .receive ? Color.sage.opacity(0.14) : .clear, in: .rect(cornerRadius: 10, style: .continuous))
        .overlay {
            if message.wakeStopped || message.direction == .send {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(message.wakeStopped ? Color.danger.opacity(0.4) : .sageLine.opacity(0.6), lineWidth: 1)
            }
        }
    }
}
