import Foundation
import Testing
@testable import Khisso

/// The job ledger, message status, routines and the events that move an agent's state.
struct AgentSurfaceTests {
    private static let agentJSON = #"""
    {"id":"a","name":"a","system_prompt":"","parent_agent_id":null,"active":true,
     "running":{"working":true,"waiting_on":null,"job":{"job":7,"requester":null,
       "opened":{"seq":7,"at":"2026-11-16T09:00:00-05:00","content":"book it"},"answer_by":"2026-11-16T09:05:00-05:00",
       "asks":[{"to":"b","seq":8,"answered_seq":null},{"to":"c","seq":9,"answered_seq":10}],"helpers":["task/browser/1"],
       "stored":["Flight"],"told":[],"reminders":["2026-11-16T16:00:00-05:00"],"stopped":null}},
     "sessions":{"tasks":[]},"created_at":"2026-10-01T00:00:00.000Z","updated_at":"2026-11-16T08:00:00.000Z"}
    """#

    private func agent() throws -> AgentRecord {
        try ServiceJSON.decoder.decode(AgentRecord.self, from: Data(Self.agentJSON.utf8))
    }

    @Test func readsTheLedgerWithWholeSecondTimes() throws {
        let job = try #require(agent().running.job)
        #expect(job.opened.seq == 7 && job.asks[1].answeredSeq == 10 && job.reminders.count == 1)
        #expect(job.answerBy == job.opened.at.addingTimeInterval(300))
    }

    @Test func mapsTheLedgerToCopy() throws {
        let agent = try agent()
        let opened = try #require(agent.running.job).opened.at
        let brief = AgentBrief.of(agent, now: opened.addingTimeInterval(240))
        #expect(brief.tone == .working && brief.ask?.who == "You")
        #expect(brief.answerBy == .init(overdue: false, label: "Answer due in 1m"))
        let late = AgentBrief.of(agent, now: opened.addingTimeInterval(540))
        #expect(late.answerBy == .init(overdue: true, label: "Answer 4m overdue"))
        #expect(agent.running.mark(at: opened.addingTimeInterval(540)) == .overdue)
        #expect(agent.running.mark(at: opened) == nil)
    }

    @Test func choosesTheSituationByPriority() throws {
        var agent = try agent()
        let job = try #require(agent.running.job)
        let now = job.opened.at.addingTimeInterval(240)
        #expect(AgentFacts.situation(agent, standing: nil, now: now) == AgentSituation(tone: .live, text: "Working · 4 min"))
        let overdue = job.opened.at.addingTimeInterval(540)
        #expect(AgentFacts.situation(agent, standing: nil, now: overdue) == AgentSituation(tone: .late, text: "Answer 4m overdue"))
        let asked = Standing(kind: .needsInput, seq: 9, content: "which date?", at: now)
        #expect(AgentFacts.situation(agent, standing: asked, now: overdue) == AgentSituation(tone: .wait, text: "Needs your input"))
        let blocked = Standing(kind: .blocked, seq: 9, content: "no login", at: now)
        #expect(AgentFacts.situation(agent, standing: blocked, now: now).text == "Blocked")
        let stopped = JobLedger(job: 7, requester: nil, opened: job.opened, answerBy: job.answerBy, stopped: .init(at: job.opened.at, by: "ankur"))
        agent.running = .init(working: false, waitingOn: nil, job: stopped)
        #expect(AgentFacts.situation(agent, standing: nil, now: now) == AgentSituation(tone: .late, text: "Stopped 4 min ago"))
        agent.running = .init(working: false, waitingOn: .init(targets: ["b"], since: now, wakesBy: now), job: nil)
        #expect(AgentFacts.situation(agent, standing: nil, now: now).text == "Waiting")
        agent.running = .quiet
        #expect(AgentFacts.situation(agent, standing: nil, now: now) == AgentSituation(tone: .rest, text: "Idle"))
    }

    @Test func listsOnlyTrueFacts() throws {
        var agent = try agent()
        let job = try #require(agent.running.job)
        let now = job.opened.at.addingTimeInterval(240)
        let names = ["b": "Bee", "c": "Sea"]
        let nameOf: (String) -> String = { names[$0] ?? $0 }
        func labels(_ input: AgentFactsInput) -> [String] { AgentFacts.facts(input).map(\.label) }
        let counts = WakeCounts(toolCalls: 7, messagesSent: 1, messagesReceived: 0)
        let working = AgentFactsInput(agent: agent, counts: counts, nameOf: nameOf, now: now)
        #expect(labels(working) == ["Asked by", "Task", "Answer due", "So far", "Asked Bee", "Asked Sea", "Saved to memory", "Checks back", "Last active", "Created"])
        #expect(AgentFacts.facts(working).first { $0.label == "So far" }?.value == "7 tool calls · 1 message sent")
        let standing = Standing(kind: .blocked, seq: 9, content: "no login\nfor the portal", at: now.addingTimeInterval(-660))
        let blocked = AgentFacts.facts(AgentFactsInput(agent: agent, standing: standing, nameOf: nameOf, now: now))
        #expect(blocked.first == AgentFact(label: "Stuck on", value: "no login for the portal", hint: "11 min ago", wrap: true, long: true))
        agent.running = .init(working: false, waitingOn: .init(targets: ["b", "task/terminal/2"], since: now.addingTimeInterval(-120), wakesBy: now), job: nil)
        let waiting = AgentFacts.facts(AgentFactsInput(agent: agent, nameOf: nameOf, now: now))
        #expect(waiting.map(\.label) == ["Waiting on", "Last active", "Created"])
        #expect(waiting[0].value == "Bee, a terminal helper" && waiting[0].hint == "for 2 min")
        agent.running = .quiet
        #expect(labels(AgentFactsInput(agent: agent, nameOf: nameOf, now: now)) == ["Last active", "Created"])
    }

    @Test func wordsHelpersWithoutAddresses() {
        let tasks = [("task/browser/1", "working"), ("task/browser/2", "asking"), ("task/terminal/3", "stopped"), ("task/terminal/4", "asleep")]
        let list = tasks.map { NasTask(task: $0.0, kind: $0.0.contains("browser") ? "browser" : "terminal", owner: "a", purpose: "p", status: $0.1, resource: nil, state: "", lastActivity: .now, activeUrl: nil) }
        #expect(AgentFacts.helperWords(list) == "1 working · 1 asking it · 2 resting")
        #expect(AgentFacts.helperWords([]) == nil)
        #expect(AgentFacts.targetWords("task/terminal/3", tasks: list, nameOf: { $0 }) == "a terminal helper")
    }

    @Test func statesAndStoppedJobs() throws {
        var agent = try agent()
        let job = try #require(agent.running.job)
        let stopped = JobLedger(job: 7, requester: nil, opened: job.opened, answerBy: job.answerBy, stopped: .init(at: job.opened.at, by: "ankur"))
        agent.running = .init(working: false, waitingOn: nil, job: stopped)
        #expect(agent.running.state == .idle && agent.running.mark(at: .now) == .stopped)
        #expect(AgentBrief.of(agent, now: .now).tone == .stopped && AgentBrief.of(agent, now: .now).answerBy == nil)
        agent.running = .init(working: false, waitingOn: .init(targets: ["b", "task/browser/1"], since: .now, wakesBy: .now), job: nil)
        #expect(agent.running.state == .waiting)
        #expect(ActivityLabel.text(agent.running, counts: nil) == "waiting on b, task/browser/1")
        agent.running = .init(working: true, waitingOn: nil, job: nil)
        #expect(ActivityLabel.text(agent.running, counts: WakeCounts(toolCalls: 3, messagesSent: 0, messagesReceived: 0)) == "working · 3 tool calls")
        #expect(ActivityLabel.text(.quiet, counts: nil) == nil)
    }

    @Test func rowsLeadWithTheAskWhileWorkingAndTheStopWhenStopped() throws {
        var agent = try agent()
        let job = try #require(agent.running.job)
        let thread = ThreadSummary(agentId: "a", agentName: "a", lastMessage: "last words", lastAt: .now, fromUser: false, unread: 0, readSeq: nil)
        #expect(ChatGroups.line(thread, running: agent.running) == "book it")
        let stopped = JobLedger(job: 7, requester: nil, opened: job.opened, answerBy: job.answerBy, stopped: .init(at: .now, by: "ankur"))
        agent.running = .init(working: false, waitingOn: nil, job: stopped)
        #expect(ChatGroups.line(thread, running: agent.running) == "Stopped just now")
        #expect(ChatGroups.line(thread, running: .quiet) == "last words")
    }

    private func message(_ seq: Int, from: String?, to: String?, status: MessageStatus?) -> DurableMessage {
        DurableMessage(seq: seq, fromAgentId: from, toAgentId: to, content: "m\(seq)", attachments: [], kind: .message, status: status, createdAt: .now)
    }

    @Test func standingFollowsTheNewestMessage() {
        #expect(Standing.of(messages: [message(1, from: "a", to: nil, status: .needsInput)], wakes: [])?.kind == .needsInput)
        #expect(Standing.of(messages: [message(1, from: "a", to: nil, status: .blocked)], wakes: [])?.kind == .blocked)
        #expect(Standing.of(messages: [message(1, from: "a", to: nil, status: .needsInput), message(2, from: nil, to: "a", status: .done)], wakes: []) == nil)
        #expect(Standing.of(messages: [message(1, from: "a", to: nil, status: .done)], wakes: []) == nil)
    }

    @Test func standingFallsBackToTheWakesWhenTheThreadCarriesNoStatus() throws {
        let json = #"""
        {"wake":{"id":"w","agent_id":"a","reason":{"kind":"message","ref":null},"opened_by":null,"started_at":"2026-11-16T10:00:00.000Z","ended_at":"2026-11-16T10:01:00.000Z","outcome":"yielded","error":null,"usage":{"calls":0,"input_tokens":0,"output_tokens":0,"cache_write":0,"cache_read":0},"counts":{"tool_calls":0,"messages_sent":1,"messages_received":1},"activity_trimmed":false},
         "entries":[{"ord":0,"at":"2026-11-16T10:00:00.000Z","type":"message","direction":"received","message":{"id":"1","seq":4,"kind":"notice","status":null,"from_agent_id":"a","to_agent_id":"a","content":"note","created_at":"2026-11-16T10:00:00.000Z","attachments":[]}},
          {"ord":1,"at":"2026-11-16T10:00:30.000Z","type":"message","direction":"sent","message":{"id":"2","seq":5,"kind":"message","status":"needs_input","from_agent_id":"a","to_agent_id":null,"content":"which date?","created_at":"2026-11-16T10:00:30.000Z","attachments":[]}}]}
        """#
        let detail = try ServiceJSON.verbatim.decode(WakeDetail.self, from: Data(json.utf8))
        let standing = Standing.of(messages: [message(5, from: "a", to: nil, status: nil)], wakes: [detail])
        #expect(standing?.kind == .needsInput && standing?.seq == 5)
    }

    @Test func wordsRoutineCadenceAndNextRun() throws {
        #expect(RoutineFormat.days(nil) == "Every day" && RoutineFormat.days([.mon, .tue, .wed, .thu, .fri]) == "Weekdays")
        #expect(RoutineFormat.days([.sun, .sat]) == "Weekends" && RoutineFormat.days([.wed, .mon]) == "Mon, Wed")
        #expect(RoutineFormat.time("09:00") == "9:00 AM" && RoutineFormat.time("00:05") == "12:05 AM" && RoutineFormat.time("x") == nil)
        let json = #"{"routines":[{"id":"r","agent_id":"a","title":"T","procedure":"P","at":"09:00","days":["mon"],"next_run_at":"2026-11-23T09:00:00.000Z","last_run_at":"2026-11-16T09:00:00.000Z","last_job_id":null,"active":true,"created_at":"2026-11-01T00:00:00.000Z"},{"id":"r2","agent_id":"a","title":"Ended","procedure":"","at":"10:00","days":null,"next_run_at":"2026-11-17T10:00:00.000Z","last_run_at":null,"active":false}],"reminders":[{"id":"m","agent_id":"a","job_id":null,"note":"N","run_at":"2026-11-16T16:00:00.000Z"}]}"#
        let routines = try ServiceJSON.decoder.decode(Routines.self, from: Data(json.utf8))
        #expect(RoutineFormat.active(routines.routines).map(\.id) == ["r"])
        #expect(RoutineFormat.cadence(routines.routines[0]) == "Mon at 9:00 AM")
        let routine = routines.routines[0]
        #expect(RoutineFormat.runs(routine, now: routine.nextRunAt.addingTimeInterval(-2 * 86_400)).hasPrefix("Next Mon ") && RoutineFormat.runs(routine, now: routine.nextRunAt).hasSuffix("last ran 1 wk ago") == false)
        #expect(RoutineFormat.runs(routine, now: routine.nextRunAt.addingTimeInterval(-86_400 * 8)).contains(","))
        #expect(AgentFacts.routinesFact(routines, now: routine.nextRunAt.addingTimeInterval(-3600))?.value == "1 routine · 1 reminder")
        #expect(AgentFacts.routinesFact(Routines(routines: [], reminders: []), now: .now) == nil)
    }

    @MainActor @Test func hidesTheRoutinesCardWhenNothingCanBeCancelled() {
        #expect(RoutinesSection.shown(.loading) && RoutinesSection.shown(.failed("x")))
        #expect(!RoutinesSection.shown(.ready(Routines(routines: [], reminders: []))))
        let reminder = Reminder(id: "m", agentId: "a", note: "n", runAt: .now)
        #expect(RoutinesSection.shown(.ready(Routines(routines: [], reminders: [reminder]))))
        #expect(RoutinesSection.count(Routines(routines: [], reminders: [reminder, reminder])) == "2 reminders")
    }

    @Test func leavesLinksReadableAndNonWebLinksPlain() throws {
        let url = try #require(LinkFormat.parseHTTP("https://www.example.com/a/very/long/path/that/keeps/going/on"))
        #expect(LinkFormat.bareLabel(url) == "example.com/a/very/long/path/that/k…" && LinkFormat.bareLabel(url).count == 36)
        #expect(LinkFormat.parseHTTP("mailto:a@b.c") == nil && LinkFormat.parseHTTP("/relative") == nil)
        #expect(LinkFormat.normalize("see https://example.com/x/, ok") == "see [example.com/x](https://example.com/x/), ok")
        #expect(LinkFormat.normalize("[https://example.com](https://example.com)") == "[example.com](https://example.com)")
        #expect(LinkFormat.normalize("[the docs](https://example.com/d)") == "[the docs](https://example.com/d)")
        #expect(LinkFormat.normalize("[mail me](mailto:a@b.c) and [x](/rel)") == "mail me and x")
        #expect(LinkFormat.normalize("`https://example.com`") == "`https://example.com`")
        #expect(LinkFormat.normalize("```\nhttps://example.com\n```") == "```\nhttps://example.com\n```")
        #expect(Agent.preview("go to [the site](https://example.com/p) now") == "go to the site now")
    }

    @Test func readsStatusAndEventsFromTheStream() async throws {
        let lines = AsyncStream<String> { continuation in
            continuation.yield(#"data: {"type":"message","agent_id":"a","from_agent_id":"a","to_agent_id":null,"content":"x","attachments":[],"seq":3,"status":"blocked","at":"2026-11-16T16:00:00.000Z"}"#)
            continuation.yield(#"data: {"type":"schedules_changed","at":"2026-11-16T16:00:00.000Z"}"#)
            continuation.finish()
        }
        var got: [HathEvent] = []
        for try await event in HathClient.events(from: lines) { got.append(event) }
        guard case .message(_, let message) = got[0] else { Issue.record("not a message"); return }
        #expect(message.status == .blocked)
        #expect(got[1] == .schedulesChanged)
    }

    @Test func tolerantInstants() {
        #expect(Date.hathInstant("2026-11-16T09:00:00-05:00") != nil && Date.hathInstant("2026-11-16T09:00:00.250Z") != nil)
        #expect(Date.hathInstant("tomorrow") == nil)
    }

    @Test func cancelsAndStopsThroughTheirRoutes() async throws {
        final class Catcher: URLProtocol {
            nonisolated(unsafe) static var seen: [String] = []
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                Catcher.seen.append("\(request.httpMethod!) \(request.url!.path)")
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(#"{"agent_id":"a","ended_run":true,"job":7,"stopped_tasks":["task/browser/1"],"halt_failed":[{"task":"task/browser/2","error":"nas"}]}"#.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Catcher.self]
        let hath = HathClient(session: URLSession(configuration: configuration))
        try await hath.cancelRoutine("r1")
        try await hath.cancelReminder("m1")
        let result = try await hath.stop(agentId: "a")
        #expect(Catcher.seen == ["DELETE /routines/r1", "DELETE /reminders/m1", "POST /agents/a/stop"])
        #expect(result.endedRun && result.haltFailed.first?.task == "task/browser/2")
    }
}
