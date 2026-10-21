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
