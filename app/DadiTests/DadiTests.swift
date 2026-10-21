import Foundation
import Testing
@testable import Khisso

/// Setup codes decode the box's provisioning bundle and reject anything else
/// with a reason the Join screen can show.
struct SetupCodeTests {
    private func encode(_ fields: [String: String]) throws -> String {
        try JSONSerialization.data(withJSONObject: fields).base64EncodedString()
    }

    @Test func decodesABoxSetupCode() throws {
        let pasted = try encode(["control_url": "http://192.0.2.10:8080", "auth_key": "key", "node_name": "iphone", "ca_pem": "ignored"])
        let code = try SetupCode(pasted: "  \(pasted)\n")
        #expect(code.controlUrl == "http://192.0.2.10:8080")
        #expect(code.authKey == "key")
        #expect(code.nodeName == "iphone")
    }

    @Test func rejectsEmptyAndGarbage() {
        #expect(throws: SetupCode.Problem.empty) { try SetupCode(pasted: "   ") }
        #expect(throws: SetupCode.Problem.unreadable) { try SetupCode(pasted: "not base64!") }
        #expect(throws: SetupCode.Problem.unreadable) { try SetupCode(pasted: Data("[1,2]".utf8).base64EncodedString()) }
    }

    @Test func namesTheMissingField() throws {
        let pasted = try encode(["control_url": "http://192.0.2.10:8080", "auth_key": " "])
        #expect(throws: SetupCode.Problem.missing("auth_key")) { try SetupCode(pasted: pasted) }
    }
}

/// Service failures carry the service's own error code and message.
struct ServiceErrorTests {
    @Test func readsTheErrorEnvelope() {
        let body = Data(#"{"error":{"type":"not_found","message":"agent finance-specialist not found"}}"#.utf8)
        let error = ServiceClient.error(status: 404, body: body)
        #expect(error == ServiceError(status: 404, type: "not_found", message: "agent finance-specialist not found"))
    }

    @Test func reportsOtherResponsesWithTheirStatus() {
        let error = ServiceClient.error(status: 502, body: Data("Bad Gateway".utf8))
        #expect(error.type == "unexpected_response")
        #expect(error.message == "HTTP 502: Bad Gateway")
    }
}

/// Hath's SSE lines become events; unknown event types pass through and a
/// malformed payload ends the stream.
struct HathEventTests {
    private func events(_ lines: [String]) async throws -> [HathEvent] {
        var out: [HathEvent] = []
        for try await event in HathClient.events(from: lines.async) {
            out.append(event)
        }
        return out
    }

    @Test func parsesMessagesAndLanes() async throws {
        let got = try await events([
            ": connected",
            "",
            #"data: {"type":"lane_started","agent_id":"finance-specialist","lane":"reasoning","at":"2026-10-21T16:00:00.000Z"}"#,
            #"data: {"type":"message","agent_id":"finance-specialist","from_agent_id":"finance-specialist","to_agent_id":null,"content":"$412 left","attachments":[],"seq":42,"at":"2026-10-21T16:00:01.250Z"}"#,
            #"data: {"type":"agent_spawned","agent_id":"x","parent_agent_id":null,"name":"x","at":"2026-10-21T16:00:02.000Z"}"#,
            ": ping",
        ])
        #expect(got.count == 3)
        #expect(got[0] == .laneStarted(agentId: "finance-specialist"))
        guard case .message(let agentId, let message) = got[1] else {
            Issue.record("second event is \(got[1])")
            return
        }
        #expect(agentId == "finance-specialist")
        #expect(message.seq == 42 && !message.fromUser && message.content == "$412 left")
        #expect(got[2] == .unhandled(type: "agent_spawned"))
    }

    @Test func malformedPayloadEndsTheStream() async {
        await #expect(throws: DecodingError.self) {
            _ = try await events(["data: {not json"])
        }
    }
}

/// An array as an async sequence of lines, standing in for an HTTP body.
private struct LineSequence: AsyncSequence, Sendable {
    let lines: [String]

    struct AsyncIterator: AsyncIteratorProtocol {
        var rest: ArraySlice<String>
        mutating func next() async -> String? { rest.popFirst() }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(rest: lines[...]) }
}

private extension Array where Element == String {
    var async: LineSequence { LineSequence(lines: self) }
}

/// The planner lays a day out as thaali does: lanes for overlaps, open time
/// between blocks, and what is now and next.
struct PlannerLayoutTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Detroit")!
        return c
    }()

    private func block(_ id: String, _ start: String, _ end: String) -> PlannerBlock {
        let day = "2026-10-21T"
        func date(_ time: String) -> Date { try! Date("\(day)\(time):00-04:00", strategy: .iso8601) }
        return PlannerBlock(id: id, startAt: date(start), endAt: date(end), title: id, note: nil, kind: "study", icon: "book", fixed: false, doneAt: nil)
    }

    private var day: Date { try! Date("2026-10-21T12:00:00-04:00", strategy: .iso8601) }

    @Test func overlapsGetSideBySideLanes() {
        let segments = PlannerLayout.segments([block("a", "09:00", "10:00"), block("b", "09:30", "10:30"), block("c", "11:00", "12:00")], on: day, calendar: calendar)
        #expect(segments.map(\.id) == ["a", "b", "c"])
        #expect(segments.map(\.lane) == [0, 1, 0])
        #expect(segments.map(\.lanes) == [2, 2, 1])
        #expect(segments[0].startMin == 540)
    }

    @Test func openTimeOfTenMinutesOrMoreIsAGap() {
        let segments = PlannerLayout.segments([block("a", "09:00", "10:00"), block("b", "10:05", "10:30"), block("c", "11:00", "12:00")], on: day, calendar: calendar)
        #expect(PlannerLayout.gaps(segments) == [PlannerLayout.Gap(startMin: 630, endMin: 660)])
    }

    @Test func findsNowAndNext() {
        let segments = PlannerLayout.segments([block("a", "09:00", "10:00"), block("b", "11:00", "12:00")], on: day, calendar: calendar)
        let during = PlannerLayout.nowAndNext(segments, at: 570)
        #expect(during.current?.id == "a" && during.next?.id == "b")
        let between = PlannerLayout.nowAndNext(segments, at: 630)
        #expect(between.current == nil && between.next?.id == "b")
    }

    @Test func spansReadAsHoursAndMinutes() {
        #expect(PlannerLayout.span(80) == "1 h 20 min")
        #expect(PlannerLayout.span(45) == "45 min")
        #expect(PlannerLayout.span(120) == "2 h")
    }
}

/// Chaavi's flat folders nest by slash, as in thaali, and counts roll up.
struct FolderTreeTests {
    private let folders = [
        ChaaviFolder(id: "1", name: "Development/fliks-gg"),
        ChaaviFolder(id: "2", name: "Development/dadi"),
        ChaaviFolder(id: "3", name: "School"),
    ]

    private func item(_ id: String, folder: String?) -> ChaaviItem {
        ChaaviItem(id: id, name: id, favorite: false, folderId: folder, type: "login", login: nil)
    }

    @Test func parentsExistFromTheirChildrensNames() {
        let items = [item("a", folder: "1"), item("b", folder: "2"), item("c", folder: "3"), item("d", folder: nil)]
        let top = FolderTree.children(of: nil, folders: folders, items: items)
        #expect(top.map(\.path) == ["Development", "School"])
        #expect(top.map(\.count) == [2, 1])
        #expect(FolderTree.children(of: "Development", folders: folders, items: items).map(\.name) == ["dadi", "fliks-gg"])
    }

    @Test func aFolderShowsItsWholeSubtree() {
        let items = [item("a", folder: "1"), item("b", folder: "2"), item("c", folder: "3")]
        #expect(FolderTree.items(in: "Development", folders: folders, items: items).map(\.id) == ["a", "b"])
        #expect(FolderTree.items(in: nil, folders: folders, items: items).count == 3)
        #expect(!FolderTree.isWithin("Developments", "Development"))
    }
}

/// The force layout settles, keeps linked nodes near, and starts known nodes where they were.
struct ForceLayoutTests {
    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }

    @Test func linksRestNearTheirLengthAndNodesStayApart() {
        var layout = ForceLayout(count: 4, links: [ForceLayout.Link(a: 0, b: 1), ForceLayout.Link(a: 2, b: 3)])
        var steps = 0
        while !layout.settled && steps < 2000 {
            layout.step()
            steps += 1
        }
        #expect(layout.settled)
        let linked = distance(layout.positions[0], layout.positions[1])
        #expect(abs(linked - layout.linkLength) < layout.linkLength / 2)
        for a in 0..<4 {
            for b in (a + 1)..<4 { #expect(distance(layout.positions[a], layout.positions[b]) > 10) }
        }
    }

    @Test func seededNodesStartWhereTheyWere() {
        let layout = ForceLayout(count: 2, links: [], seed: [1: CGPoint(x: 300, y: -40)], alpha: 0.25)
        #expect(layout.positions[1] == CGPoint(x: 300, y: -40))
        #expect(layout.alpha == 0.25)
    }

    @Test func aMemorySizedNetworkSettlesQuickly() {
        let count = 1050
        let links = (1..<count).map { ForceLayout.Link(a: $0, b: ($0 * 7) % $0) }
        var layout = ForceLayout(count: count, links: links)
        let clock = ContinuousClock()
        let took = clock.measure {
            while !layout.settled { layout.step() }
        }
        #expect(layout.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        print("force layout of \(count) nodes settled in \(took)")
    }
}
