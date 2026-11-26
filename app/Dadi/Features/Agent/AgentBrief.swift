import Foundation

/// The job ledger as the agent sheet reads it: the agent's tone, the ask that opened its job and the answer clock.
struct AgentBrief: Equatable {
    /// The one word the sheet's top reads as.
    enum Tone: Equatable {
        case working, waiting, idle, stopped
    }

    /// Who gave the agent the job and what they said.
    struct Ask: Equatable {
        /// `You`, an agent id, or `Routine` when the agent started the run itself.
        let who: String
        let at: Date
        let text: String
        let routine: Bool
    }

    /// Where the answer stands against its due time.
    struct AnswerBy: Equatable {
        let overdue: Bool
        let label: String
    }

    let tone: Tone
    let ask: Ask?
    /// Nil once the requester has been told, once the job is stopped, and for jobs with no answer time.
    let answerBy: AnswerBy?

    /// The answer clock: "Answer due in 3m", or "Answer 2m overdue" once it passed.
    static func answerBy(_ job: JobLedger, now: Date) -> AnswerBy? {
        guard let due = job.answerBy, job.told.isEmpty else { return nil }
        let seconds = due.timeIntervalSince(now)
        return seconds >= 0
            ? AnswerBy(overdue: false, label: "Answer due in \(WakeFormat.span(seconds))")
            : AnswerBy(overdue: true, label: "Answer \(WakeFormat.span(-seconds)) overdue")
    }

    /// The ask of a job: whose message opened it, and what it said.
    static func ask(_ job: JobLedger, agentId: String) -> Ask {
        let routine = job.requester == agentId
        return Ask(who: routine ? "Routine" : job.requester ?? "You", at: job.opened.at, text: job.opened.content, routine: routine)
    }

    /// The agent's job ledger as the sheet reads it. Stopped wins over a wait; a running loop wins over a stopped
    /// job it has moved past; the ledger's rows read as given, never as a count of what needs Ankur.
    static func of(_ agent: AgentRecord, now: Date) -> AgentBrief {
        let running = agent.running
        let job = running.job
        let tone: Tone = running.working ? .working : job?.stopped != nil ? .stopped : running.waitingOn != nil ? .waiting : .idle
        return AgentBrief(
            tone: tone,
            ask: job.map { ask($0, agentId: agent.id) },
            answerBy: job == nil || tone == .stopped ? nil : answerBy(job!, now: now)
        )
    }
}

/// What the agent's newest message to Ankur leaves open, above everything else on the sheet: it is parked on his
/// answer, or blocked.
struct Standing: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case needsInput, blocked
    }

    let kind: Kind
    let seq: Int
    let content: String
    let at: Date

    /// The standing a message leaves, nil for `done`, no status, or any other.
    private static func standing(_ status: MessageStatus?, seq: Int, content: String, at: Date) -> Standing? {
        switch status {
        case .needsInput: Standing(kind: .needsInput, seq: seq, content: content, at: at)
        case .blocked: Standing(kind: .blocked, seq: seq, content: content, at: at)
        case .done, nil: nil
        }
    }

    /// What the agent's newest human-thread message leaves open. A newer message from Ankur settles it. Read from
    /// the thread when Hath's thread route carries `status`; otherwise from the human messages in `wakes` (newest
    /// first), where the wake routes do carry it: the first one found, sent to Ankur or received from him, decides.
    static func of(messages: [DurableMessage], wakes: [WakeDetail]) -> Standing? {
        let human = messages.filter { $0.kind != .notice && $0.kind != .utterance }
        if let newest = human.max(by: { $0.seq < $1.seq }), newest.status != nil {
            return newest.fromUser ? nil : standing(newest.status, seq: newest.seq, content: newest.content, at: newest.createdAt)
        }
        for detail in wakes {
            for entry in detail.entries.reversed() {
                guard case .message(let entry) = entry, entry.message.kind == .message else { continue }
                let message = entry.message
                if message.fromAgentId == nil { return nil }
                if message.toAgentId == nil {
                    return standing(message.status, seq: message.seq, content: message.content, at: message.createdAt)
                }
            }
        }
        return nil
    }

    /// How many of the newest thread messages and wakes are read for it.
    static let threadMessages = 5
    static let recentWakes = 3

    /// Reads what the thread of `agentId` still waits on: its newest messages and its newest wakes.
    static func read(hath: HathClient, agentId: String) async throws -> Standing? {
        let messages = try await hath.messages(agentId: agentId, limit: threadMessages)
        if messages.contains(where: { $0.status != nil }) { return of(messages: messages, wakes: []) }
        let page = try await hath.wakes(agentId: agentId, limit: recentWakes)
        var details: [WakeDetail] = []
        for wake in page.wakes.prefix(recentWakes) { details.append(try await hath.wake(agentId: agentId, wakeId: wake.id)) }
        return of(messages: messages, wakes: details)
    }
}
