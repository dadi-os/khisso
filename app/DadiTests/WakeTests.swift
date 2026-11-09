import Foundation
import Testing
@testable import Khisso

/// Copies of the example wakes in the messages-and-logs design contract.
private enum WakeExamples {
    static let running = #"""
    {"wake":{"id":"0b6f7d5e-6a0c-4b1e-9a43-2f1d7c3a1001","agent_id":"networking-specialist","reason":{"kind":"message","ref":"career-manager"},
      "opened_by":{"id":"7c1e2b9a-3d4f-4e55-8a10-5b2f9e000001","seq":23923,"kind":"message","status":null,"from_agent_id":null,"to_agent_id":"networking-specialist","content":"I will close the linkedin premium, as for networking, this continues...","created_at":"2026-11-06T03:54:22.551Z","attachments":[]},
      "started_at":"2026-11-06T03:54:22.600Z","ended_at":null,"outcome":"running","error":null,
      "usage":{"calls":14,"input_tokens":52,"output_tokens":21340,"cache_write":188200,"cache_read":940100},
      "counts":{"tool_calls":22,"messages_sent":1,"messages_received":1},"activity_trimmed":false},
     "entries":[
      {"ord":0,"at":"2026-11-06T03:54:22.551Z","type":"message","direction":"received","message":{"id":"7c1e2b9a-3d4f-4e55-8a10-5b2f9e000001","seq":23923,"kind":"message","status":null,"from_agent_id":null,"to_agent_id":"networking-specialist","content":"I will close the linkedin premium, as for networking, this continues...","created_at":"2026-11-06T03:54:22.551Z","attachments":[]}},
      {"ord":1,"at":"2026-11-06T03:54:25.100Z","type":"turn","lane":"process","usage":{"input_tokens":4,"output_tokens":312,"cache_write":1200,"cache_read":22000},"thinking":"Ankur wants LinkedIn replies drafted and sent...","text":null,
       "calls":[{"id":"toolu_01A","name":"steer_work","input":{"instruction":"Go through LinkedIn backlog..."},"log_id":"a1f0c0de-0000-4000-8000-000000000011","result":{"content":"{\"queued\":true,\"running\":false,\"terminated\":false}","is_error":false,"truncated":false,"chars":52}}]},
      {"ord":2,"at":"2026-11-06T03:54:27.777Z","type":"message","direction":"sent","message":{"id":"7c1e2b9a-3d4f-4e55-8a10-5b2f9e000002","seq":23924,"kind":"message","status":"running","from_agent_id":"networking-specialist","to_agent_id":null,"content":"Got it. I'm going through the LinkedIn backlog now...","created_at":"2026-11-06T03:54:27.777Z","attachments":[]}},
      {"ord":3,"at":"2026-11-06T03:55:02.000Z","type":"turn","lane":"work","usage":{"input_tokens":4,"output_tokens":2100,"cache_write":15200,"cache_read":60700},"thinking":"I should read the tracker first...","text":"Starting with the LinkedIn browser task.",
       "calls":[{"id":"toolu_01B","name":"steer_browser","input":{"id":"task/browser/4fa9b970","message":"Read only..."},"log_id":"a1f0c0de-0000-4000-8000-000000000012","result":null}]}]}
    """#

    static let failed = #"""
    {"id":"0b6f7d5e-6a0c-4b1e-9a43-2f1d7c3a1002","agent_id":"efficiency-specialist","reason":{"kind":"schedule","ref":"5e0a7b1c-1111-4c22-9d33-aaaaaaaaaa01"},"opened_by":null,
     "started_at":"2026-11-08T22:00:00.120Z","ended_at":"2026-11-08T22:06:41.900Z","outcome":"failed","error":"work lane stopped: prompt reached the 96000-token ceiling",
     "usage":{"calls":31,"input_tokens":120,"output_tokens":64020,"cache_write":910400,"cache_read":2710000},
     "counts":{"tool_calls":44,"messages_sent":0,"messages_received":0},"activity_trimmed":false}
    """#

    static let trimmed = #"""
    {"id":"0b6f7d5e-6a0c-4b1e-9a43-2f1d7c3a1003","agent_id":"finance-specialist","reason":{"kind":"message","ref":"efficiency-specialist"},
     "opened_by":{"id":"7c1e2b9a-3d4f-4e55-8a10-5b2f9e000003","seq":22641,"kind":"message","status":null,"from_agent_id":"efficiency-specialist","to_agent_id":"finance-specialist","content":"Review this month's card statements.","created_at":"2026-10-31T00:26:58.495Z","attachments":[]},
     "started_at":"2026-10-31T00:26:58.600Z","ended_at":"2026-10-31T00:41:12.000Z","outcome":"yielded","error":null,
     "usage":{"calls":0,"input_tokens":0,"output_tokens":0,"cache_write":0,"cache_read":0},
     "counts":{"tool_calls":0,"messages_sent":2,"messages_received":1},"activity_trimmed":true}
    """#

    static let scheduleOpened = #"""
    {"id":"0b6f7d5e-6a0c-4b1e-9a43-2f1d7c3a1004","agent_id":"networking-specialist","reason":{"kind":"schedule","ref":"9a8b7c6d-2222-4d33-8e44-bbbbbbbbbb02"},
     "opened_by":{"id":"7c1e2b9a-3d4f-4e55-8a10-5b2f9e000004","seq":24101,"kind":"message","status":null,"from_agent_id":"networking-specialist","to_agent_id":"networking-specialist","content":"8:00 AM send: send today's queued rows.","created_at":"2026-11-09T13:00:00.000Z","attachments":[]},
     "started_at":"2026-11-09T13:00:00.050Z","ended_at":"2026-11-09T13:09:30.000Z","outcome":"waiting","error":null,
     "usage":{"calls":9,"input_tokens":36,"output_tokens":9800,"cache_write":70100,"cache_read":402000},
     "counts":{"tool_calls":11,"messages_sent":0,"messages_received":1},"activity_trimmed":false}
    """#

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try ServiceJSON.verbatim.decode(type, from: Data(json.utf8))
    }
}

/// Wakes decode from Hath's example payloads, and read in the words the popover uses.
struct WakeDecodingTests {
    @Test func decodesARunningWakeWithItsOpeningMessage() throws {
        let detail = try WakeExamples.decode(WakeDetail.self, WakeExamples.running)
        let wake = detail.wake
        #expect(wake.outcome == .running && wake.endedAt == nil)
        #expect(wake.reason == WakeReason(kind: .message, ref: "career-manager"))
        #expect(wake.openedBy?.seq == 23923 && wake.openedBy?.fromAgentId == nil)
        #expect(wake.usage.cacheRead == 940_100 && wake.counts.toolCalls == 22)
    }

    @Test func decodesTheOtherExampleWakes() throws {
        let failed = try WakeExamples.decode(WakeSummary.self, WakeExamples.failed)
        #expect(failed.outcome == .failed && failed.openedBy == nil)
        #expect(failed.error == "work lane stopped: prompt reached the 96000-token ceiling")
        let trimmed = try WakeExamples.decode(WakeSummary.self, WakeExamples.trimmed)
        #expect(trimmed.activityTrimmed && trimmed.usage.calls == 0)
        let scheduled = try WakeExamples.decode(WakeSummary.self, WakeExamples.scheduleOpened)
        #expect(scheduled.outcome == .waiting && scheduled.reason.kind == .schedule)
        #expect(scheduled.openedBy?.toAgentId == "networking-specialist")
    }

    @Test func decodesAPageWithItsCursorKeptAsSent() throws {
        let json = #"{"wakes":[\#(WakeExamples.trimmed)],"next_before":{"started_at":"2026-10-31T00:26:58.600Z","id":"0b6f7d5e-6a0c-4b1e-9a43-2f1d7c3a1003"}}"#
        let page = try WakeExamples.decode(WakePage.self, json)
        #expect(page.wakes.count == 1)
        #expect(page.nextBefore == WakeCursor(startedAt: "2026-10-31T00:26:58.600Z", id: "0b6f7d5e-6a0c-4b1e-9a43-2f1d7c3a1003"))
        let last = try WakeExamples.decode(WakePage.self, #"{"wakes":[],"next_before":null}"#)
        #expect(last.nextBefore == nil)
    }

    @Test func keepsToolInputKeysAsTheAgentWroteThem() throws {
        let detail = try WakeExamples.decode(WakeDetail.self, WakeExamples.running)
        guard case .turn(let turn) = detail.entries[3] else { return Issue.record("entry 3 is not a turn") }
        #expect(turn.calls[0].input.object?["id"]?.string == "task/browser/4fa9b970")
        #expect(turn.calls[0].result == nil && turn.calls[0].logId == "a1f0c0de-0000-4000-8000-000000000012")
    }

    @Test func labelsOutcomesAndReasons() throws {
        #expect([WakeOutcome.running, .waiting, .yielded, .failed].map(WakeFormat.label) == ["Running", "Waiting", "Yielded", "Failed"])
        let names = ["career-manager": "Career manager"]
        let nameOf: (String) -> String = { names[$0] ?? $0 }
        #expect(WakeFormat.reason(WakeReason(kind: .message, ref: "career-manager"), nameOf: nameOf) == "Opened by Career manager")
        #expect(WakeFormat.reason(WakeReason(kind: .message, ref: nil), nameOf: nameOf) == "Opened by Ankur")
        #expect([WakeReasonKind.schedule, .recovery, .steer, .manual].map { WakeFormat.reason(WakeReason(kind: $0, ref: nil), nameOf: nameOf) } == ["Schedule", "Recovery", "Steer", "Manual"])
    }

    @Test func summarisesCountsUsageAndDuration() throws {
        let running = try WakeExamples.decode(WakeDetail.self, WakeExamples.running).wake
        #expect(WakeFormat.counts(running.counts) == "22 tool calls · 1 in · 1 out")
        #expect(WakeFormat.counts(WakeCounts(toolCalls: 1, messagesSent: 0, messagesReceived: 0)) == "1 tool call")
        #expect(WakeFormat.counts(WakeCounts(toolCalls: 0, messagesSent: 0, messagesReceived: 0)) == "")
        #expect(WakeFormat.usage(running.usage) == "21.4k tok · 940.1k cached")
        let failed = try WakeExamples.decode(WakeSummary.self, WakeExamples.failed)
        #expect(WakeFormat.duration(failed, now: .now) == "7m")
        #expect(WakeFormat.duration(running, now: running.startedAt.addingTimeInterval(95)) == "2m")
        #expect(WakeFormat.span(12) == "12s" && WakeFormat.span(3900) == "1h 5m")
    }
}

/// An open wake shows its entries oldest to newest under a lane filter, and the Now line reads the work lane.
struct WakeEntriesTests {
    private func entries() throws -> [WakeEntry] {
        try WakeExamples.decode(WakeDetail.self, WakeExamples.running).entries
    }

    @Test func keepsEntriesOldestToNewest() throws {
        #expect(try entries().map(\.ord) == [0, 1, 2, 3])
    }

    @Test func filtersTurnsByLaneAndKeepsEveryMessage() throws {
        let all = try entries()
        #expect(LaneFilter.all.apply(to: all).map(\.ord) == [0, 1, 2, 3])
        #expect(LaneFilter.work.apply(to: all).map(\.ord) == [0, 2, 3])
        #expect(LaneFilter.process.apply(to: all).map(\.ord) == [0, 1, 2])
    }

    @Test func derivesTheNowLineFromTheWorkLanesLatestCall() throws {
        let line = try #require(WakeFormat.currentCall(entries()))
        #expect(line.name == "steer_browser" && line.target == "task/browser/4fa9b970" && line.running)
        #expect(WakeFormat.currentCall(Array(entries().prefix(3))) == nil)
    }

    @Test func aFinishedCallIsNotRunning() throws {
        let json = WakeExamples.running.replacingOccurrences(of: #""log_id":"a1f0c0de-0000-4000-8000-000000000012","result":null"#, with: #""log_id":"a1f0c0de-0000-4000-8000-000000000012","result":{"content":"ok","is_error":false,"truncated":false,"chars":2}"#)
        let line = try #require(WakeFormat.currentCall(WakeExamples.decode(WakeDetail.self, json).entries))
        #expect(!line.running)
    }

    @Test func namesATargetFromTheMostTellingKey() {
        let input = JSONValue.object(["note": .string("x"), "message": .string("later"), "url": .string("  https://a.test/\n  page ")])
        #expect(WakeFormat.target(input) == "https://a.test/ page")
        #expect(WakeFormat.target(.object(["n": .number(1)])) == "")
        #expect(WakeFormat.target(.object(["query": .string(String(repeating: "a", count: 100))])).count == 72)
    }

    @Test func showsInputsAndResultsIndented() {
        #expect(WakeFormat.pretty(text: #"{"b":1,"a":[2]}"#) == "{\n  \"a\" : [\n    2\n  ],\n  \"b\" : 1\n}")
        #expect(WakeFormat.pretty(text: #"{"cut":"unfinished"#) == #"{"cut":"unfinished"#)
        #expect(WakeFormat.pretty(.string("plain words")) == "plain words")
    }
}

/// A newer first page keeps the older wakes already loaded.
struct WakeMergeTests {
    private func wake(_ id: String, at: String) throws -> WakeSummary {
        let json = WakeExamples.failed
            .replacingOccurrences(of: "0b6f7d5e-6a0c-4b1e-9a43-2f1d7c3a1002", with: id)
            .replacingOccurrences(of: "2026-11-08T22:00:00.120Z", with: at)
        return try WakeExamples.decode(WakeSummary.self, json)
    }

    @Test func keepsHeldWakesOlderThanTheFreshPage() throws {
        let old = try wake("old", at: "2026-11-01T10:00:00.000Z")
        let mid = try wake("mid", at: "2026-11-03T10:00:00.000Z")
        let new = try wake("new", at: "2026-11-05T10:00:00.000Z")
        #expect(WakeTimeline.merged([mid, old], with: [new, mid]).map(\.id) == ["new", "mid", "old"])
        #expect(WakeTimeline.merged([mid], with: []).map(\.id) == ["mid"])
    }
}

/// Stopping a task: what Hath's refusals say, the wake events, and where the halt goes.
struct HaltTests {
    @Test func saysARefusedHaltInPlainWords() {
        #expect(WakeFormat.haltSentence(ServiceError(status: 404, type: "task_not_found", message: "x")) == "That task no longer exists.")
        #expect(WakeFormat.haltSentence(ServiceError(status: 409, type: "task_conflict", message: "x")) == "The task changed while stopping it; try again.")
        #expect(WakeFormat.haltSentence(ServiceError(status: 502, type: "bad_gateway", message: "x")) == "Nas did not answer, so the task was not stopped.")
        #expect(WakeFormat.haltSentence(ServiceError(status: 500, type: "other", message: "Hath's words")) == "Hath's words")
    }

    @Test func readsWakeEventsAsOneKindOfChange() async throws {
        let lines = AsyncStream<String> { continuation in
            continuation.yield(#"data: {"type":"wake_started","agent_id":"a","wake_id":"w1","reason":{"kind":"message","ref":null},"at":"2026-11-09T13:00:00.000Z"}"#)
            continuation.yield(#"data: {"type":"wake_ended","agent_id":"a","wake_id":"w1","outcome":"yielded","at":"2026-11-09T13:01:00.000Z"}"#)
            continuation.yield(#"data: {"type":"wake_activity","agent_id":"a","wake_id":"w1","counts":{"tool_calls":1,"messages_sent":0,"messages_received":0}}"#)
            continuation.finish()
        }
        var got: [HathEvent] = []
        for try await event in HathClient.events(from: lines) { got.append(event) }
        #expect(got == Array(repeating: .wakeChanged(agentId: "a", wakeId: "w1"), count: 3))
    }

    @Test func sendsTheTaskAddressAsOnePathSegment() async throws {
        let url = try await Self.haltURL(agentId: "networking-specialist", taskId: "task/browser/4fa9b970")
        #expect(url.absoluteString == "http://hath.dadi/agents/networking-specialist/sessions/task%2Fbrowser%2F4fa9b970/halt")
    }

    /// The URL `haltSession` requests, caught before any network.
    private static func haltURL(agentId: String, taskId: String) async throws -> URL {
        final class Catcher: URLProtocol {
            nonisolated(unsafe) static var url: URL?
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                Catcher.url = request.url
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(#"{"task":{}}"#.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Catcher.self]
        try await HathClient(session: URLSession(configuration: configuration)).haltSession(agentId: agentId, taskId: taskId)
        return try #require(Catcher.url)
    }
}
