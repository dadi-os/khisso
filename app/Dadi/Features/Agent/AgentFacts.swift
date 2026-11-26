import Foundation

/// The words of time the agent sheet uses, as thaali's: the fewest honest words, never a raw timestamp.
enum AgentTime {
    /// How long, in the fewest honest words: "under a minute", "4 min", "2 h 10 min", "3 d".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(abs(seconds) / 60)
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 {
            let rest = minutes % 60
            return hours < 3 && rest > 0 ? "\(hours) h \(rest) min" : "\(hours) h"
        }
        return "\(hours / 24) d"
    }

    /// "4 min ago" or "in 4 min" for `date` against `now`; "just now" inside a minute.
    static func relative(_ date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if abs(seconds) < 60 { return "just now" }
        return seconds < 0 ? "\(duration(seconds)) ago" : "in \(duration(seconds))"
    }

    /// How long ago `date` was, in full words: "4 minutes ago".
    static func ago(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// A time of day: "4:18 AM".
    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// The clock time of `date`, with the day when it is not today: "Tue, Nov 17, 4:00 PM".
    static func clockWithDay(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: now) ? clock(date) : "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())), \(clock(date))"
    }
}

/// What is true of an agent now, in the one line under its name: a dot tone and a short phrase.
struct AgentSituation: Equatable {
    let tone: SituationTone
    let text: String
}

/// One labelled fact of the agent sheet.
struct AgentFact: Equatable, Identifiable {
    enum Tone: Equatable {
        case normal, late
    }

    let label: String
    let value: String
    /// The value is this agent's name, drawn as a link that opens it.
    var agentId: String?
    /// A quiet second fact after the value.
    var hint: String?
    var tone = Tone.normal
    /// The value is words and may take two lines.
    var wrap = false
    /// The value is an agent's own message and may take four lines.
    var long = false

    var id: String { label }
}

/// What the agent sheet's facts block says, read from the agent's record and what the sheet loaded around it.
struct AgentFactsInput {
    let agent: AgentRecord
    /// The agent's parent, when the page knows it.
    var parent: (id: String, name: String)?
    var routines: Routines?
    /// What the newest message to Ankur leaves open.
    var standing: Standing?
    /// What the running wake has done so far.
    var counts: WakeCounts?
    /// The agent's helper tasks as Nas reports them now.
    var tasks: [NasTask] = []
    let nameOf: (String) -> String
    let now: Date
}

/// The agent sheet's copy: its situation line and the facts block, each fact only when it is true.
enum AgentFacts {
    /// The agent's situation, the most pressing first: it needs Ankur's answer, it is blocked, it was stopped, its
    /// answer is overdue, it works, it waits, or it is idle.
    static func situation(_ agent: AgentRecord, standing: Standing?, now: Date) -> AgentSituation {
        if let standing {
            return standing.kind == .blocked ? AgentSituation(tone: .late, text: "Blocked") : AgentSituation(tone: .wait, text: "Needs your input")
        }
        let brief = AgentBrief.of(agent, now: now)
        let job = agent.running.job
        if brief.tone == .stopped, let stopped = job?.stopped {
            return AgentSituation(tone: .late, text: "Stopped \(AgentTime.relative(stopped.at, now: now))")
        }
        if let answerBy = brief.answerBy, answerBy.overdue { return AgentSituation(tone: .late, text: answerBy.label) }
        switch brief.tone {
        case .working: return AgentSituation(tone: .live, text: job.map { "Working · \(AgentTime.duration(now.timeIntervalSince($0.opened.at)))" } ?? "Working")
        case .waiting: return AgentSituation(tone: .wait, text: "Waiting")
        case .idle, .stopped: return AgentSituation(tone: .rest, text: "Idle")
        }
    }

    /// What a wait names in words: an agent by name, a helper by its kind ("a terminal helper"), never an address.
    static func targetWords(_ target: String, tasks: [NasTask], nameOf: (String) -> String) -> String {
        guard target.hasPrefix("task/") else { return nameOf(target) }
        let kind = tasks.first { $0.task == target }?.kind ?? (target.hasPrefix("task/terminal/") ? "terminal" : "browser")
        return "a \(kind) helper"
    }

    /// The helper tasks as one fact: only the counts that are true, working first.
    static func helperWords(_ tasks: [NasTask]) -> String? {
        let working = tasks.filter { $0.status == "working" || $0.status == "paused" }.count
        let asking = tasks.filter { $0.status == "asking" }.count
        let resting = tasks.count - working - asking
        let parts = [working > 0 ? "\(working) working" : nil, asking > 0 ? "\(asking) asking it" : nil, resting > 0 ? "\(resting) resting" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The routines and reminders as one fact: how many, and when the next routine runs.
    static func routinesFact(_ list: Routines, now: Date) -> AgentFact? {
        let routines = RoutineFormat.active(list.routines)
        let parts = [
            routines.isEmpty ? nil : "\(routines.count) \(routines.count == 1 ? "routine" : "routines")",
            list.reminders.isEmpty ? nil : "\(list.reminders.count) \(list.reminders.count == 1 ? "reminder" : "reminders")",
        ].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        let next = routines.min { $0.nextRunAt < $1.nextRunAt }
        return AgentFact(label: "Routines", value: parts.joined(separator: " · "), hint: next.map { "next \(RoutineFormat.nextWords($0.nextRunAt, now: now))" })
    }

    /// The agent's facts in the order the sheets keep. Nothing is listed because Hath returned it: no ids, no empty
    /// rows, a count only when the agent did that much.
    static func facts(_ input: AgentFactsInput) -> [AgentFact] {
        let agent = input.agent
        let now = input.now
        let brief = AgentBrief.of(agent, now: now)
        let job = agent.running.job
        var facts: [AgentFact] = []
        if let standing = input.standing {
            facts.append(AgentFact(label: standing.kind == .blocked ? "Stuck on" : "Asked you", value: oneLine(standing.content), hint: AgentTime.relative(standing.at, now: now), wrap: true, long: true))
        }
        if let job, let ask = brief.ask {
            facts.append(AgentFact(label: ask.routine ? "Started by" : "Asked by", value: ask.routine ? "Its own routine" : job.requester.map(input.nameOf) ?? "You", hint: AgentTime.relative(job.opened.at, now: now)))
            facts.append(AgentFact(label: ask.routine ? "Procedure" : "Task", value: oneLine(ask.text), wrap: true))
        }
        if let answerBy = brief.answerBy, let due = job?.answerBy {
            facts.append(AgentFact(label: answerBy.overdue ? "Answer was due" : "Answer due", value: AgentTime.relative(due, now: now), hint: AgentTime.clockWithDay(due, now: now), tone: answerBy.overdue ? .late : .normal))
        }
        if brief.tone == .working, let counts = input.counts, counts.toolCalls > 0 || counts.messagesSent > 0 {
            facts.append(AgentFact(label: "So far", value: WakeFormat.counts(counts)))
        }
        if brief.tone == .waiting, let waiting = agent.running.waitingOn {
            facts.append(AgentFact(label: "Waiting on", value: waiting.targets.map { targetWords($0, tasks: input.tasks, nameOf: input.nameOf) }.joined(separator: ", "), hint: "for \(AgentTime.duration(now.timeIntervalSince(waiting.since)))", wrap: true))
        }
        if brief.tone == .stopped, let stopped = job?.stopped {
            facts.append(AgentFact(label: "Stopped", value: "by \(stopped.by == "ankur" ? "you" : input.nameOf(stopped.by))", hint: AgentTime.relative(stopped.at, now: now)))
        }
        for ask in job?.asks ?? [] {
            facts.append(AgentFact(label: "Asked \(input.nameOf(ask.to))", value: ask.answeredSeq == nil ? "No reply yet" : "Replied"))
        }
        if let told = job?.told.last, let job {
            facts.append(AgentFact(label: brief.ask?.routine == true ? "Sent" : "Told you", value: oneLine(told.preview), hint: job.told.count > 1 ? "\(job.told.count) messages" : nil, wrap: true))
        }
        if let stored = job?.stored, !stored.isEmpty {
            facts.append(AgentFact(label: "Saved to memory", value: stored.joined(separator: ", "), wrap: true))
        }
        if let check = job?.reminders.first {
            facts.append(AgentFact(label: "Checks back", value: AgentTime.relative(check, now: now), hint: AgentTime.clockWithDay(check, now: now)))
        }
        if let parent = input.parent { facts.append(AgentFact(label: "Reports to", value: parent.name, agentId: parent.id)) }
        if let helpers = helperWords(input.tasks) { facts.append(AgentFact(label: "Helpers", value: helpers)) }
        if let routines = input.routines, let fact = routinesFact(routines, now: now) { facts.append(fact) }
        facts.append(AgentFact(label: "Last active", value: AgentTime.relative(agent.updatedAt, now: now)))
        facts.append(AgentFact(label: "Created", value: agent.createdAt.formatted(.dateTime.day().month(.abbreviated).year()), hint: AgentTime.relative(agent.createdAt, now: now)))
        return facts
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
