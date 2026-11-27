import Foundation
import Testing
@testable import Khisso

struct MessageDecodingTests {
    /// The shape GET /agents/:id/messages answers with: a message's files are `box://` links in its text.
    @Test func decodesAMessage() throws {
        let json = """
        {"messages":[{"id":"6d5b2030","seq":26272,"from_agent_id":"finance-specialist","to_agent_id":null,"content":"Venmo: kept.","kind":"message","created_at":"2026-11-17T19:14:55.568Z"}]}
        """
        struct Response: Decodable { let messages: [DurableMessage] }
        let message = try ServiceJSON.decoder.decode(Response.self, from: Data(json.utf8)).messages[0]
        #expect(message.seq == 26272)
        #expect(!message.fromUser)
    }

    @Test func namesTheMissingKey() {
        struct Needs: Decodable { let seq: Int }
        do { _ = try ServiceJSON.decoder.decode(Needs.self, from: Data("{}".utf8)) } catch let error as DecodingError {
            #expect(ServiceClient.describe(error).contains("missing \"seq\""))
        } catch { Issue.record("not a decoding error") }
    }
}
