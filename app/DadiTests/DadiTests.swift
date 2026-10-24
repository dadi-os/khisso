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
        #expect(got[0] == .laneStarted(agentId: "finance-specialist", lane: .reasoning))
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

/// The box's /status as it answers today: the system disk is usage only,
/// while each drive names itself and its mount.
struct NasStatusTests {
    @Test func decodesTheLiveStatus() throws {
        let body = #"""
        {"uptime_seconds":17520,"services":[{"name":"yaad","healthy":true},{"name":"nas","healthy":true}],
         "disk":{"free_bytes":213617405952,"total_bytes":248154361856,"used_percent":13.9},
         "disks":[{"name":"nvme0n1","model":"KINGSTON","transport":"nvme","mount":"/sysroot","free_bytes":213617401856,"total_bytes":248154361856,"used_percent":13.9}],
         "cpu":{"name":"AMD Ryzen 7 3750H","used_percent":30.5},
         "memory":{"name":"System memory","used_bytes":4566728704,"total_bytes":8110702592,"used_percent":56.3},
         "errors":[]}
        """#
        let status = try ServiceJSON.decoder.decode(NasStatus.self, from: Data(body.utf8))
        #expect(status.disk.usedPercent == 13.9)
        #expect(status.disks.map(\.mount) == ["/sysroot"])
        #expect(status.services.count == 2)
    }
}

/// Thaali's thinking mark: each dot swells in at the left and fades off the right.
struct ThinkingMarkTests {
    @Test func dotsFlowLeftToRightAndFadeAtTheEnds() {
        let start = ThinkingMark.pose(0, ms: 0)
        let middle = ThinkingMark.pose(0, ms: 750)
        #expect(start.opacity < 0.01)
        #expect(abs(middle.opacity - 1) < 0.01)
        #expect(middle.center.x > start.center.x)
        #expect(ThinkingMark.pose(0, ms: 1400).center.y > middle.center.y)
    }
}

/// An attachment is kept under its own folder with its original name, made
/// safe as one path component.
struct AttachmentFileTests {
    private func file(id: String, filename: String) -> AttachmentSummary {
        AttachmentSummary(id: id, filename: filename, mediaType: "application/pdf", sizeBytes: 10, description: nil)
    }

    @Test func keepsTheOriginalNameInAFolderPerAttachment() {
        let root = URL(filePath: "/tmp/attachments", directoryHint: .isDirectory)
        let url = AttachmentFile.url(for: file(id: "att_1", filename: "Syllabus Fall 2026.pdf"), in: root)
        #expect(url.path(percentEncoded: false) == "/tmp/attachments/att_1/Syllabus Fall 2026.pdf")
    }

    @Test func makesANameOnePathComponent() {
        #expect(AttachmentFile.name("../etc/passwd") == "..-etc-passwd")
        #expect(AttachmentFile.name("a:b.txt") == "a-b.txt")
        #expect(AttachmentFile.name("  notes.md \n") == "notes.md")
        #expect(AttachmentFile.name("") == "attachment")
        #expect(AttachmentFile.name("..") == "attachment")
    }
}

/// Hath's read state: each thread's unread count and mark, and the event that
/// tells every device a thread was read.
struct ReadStateTests {
    @Test func decodesThreadsWithTheirReadMark() throws {
        let body = #"{"agent_id":"finance-specialist","agent_name":"finance-specialist","last_message":"$412 left","last_at":"2026-10-22T13:00:00.000Z","from_user":false,"unread":3,"read_seq":null}"#
        let thread = try ServiceJSON.decoder.decode(ThreadSummary.self, from: Data(body.utf8))
        #expect(thread.unread == 3)
        #expect(thread.readSeq == nil)
    }

    @Test func decodesThreadReadEvents() async throws {
        let lines = [#"data: {"type":"thread_read","agent_id":"finance-specialist","read_seq":42,"unread":0,"at":"2026-10-22T13:00:00.000Z"}"#]
        var got: [HathEvent] = []
        for try await event in HathClient.events(from: lines.async) { got.append(event) }
        #expect(got == [.threadRead(agentId: "finance-specialist", readSeq: 42, unread: 0)])
    }
}

/// Math in previews and on the watch reads as Unicode, by the same rule the
/// thread renders by, while money stays money.
struct UnicodeMathTests {
    @Test func readsInlineMathAsSymbols() {
        #expect(UnicodeMath.text(#"Rent $\rightarrow$ savings"#) == "Rent → savings")
        #expect(UnicodeMath.text(#"\(a \le b \ne c\) and \(x \to \infty\)"#) == "a ≤ b ≠ c and x → ∞")
        #expect(UnicodeMath.text(#"$\alpha + \beta \approx \pi$"#) == "α + β ≈ π")
        #expect(UnicodeMath.text(#"\(3 \times 4 \cdot 2 \pm 1\)"#) == "3 × 4 · 2 ± 1")
        #expect(UnicodeMath.text(#"$A \Rightarrow B \leftarrow C \geq D$"#) == "A ⇒ B ← C ≥ D")
    }

    @Test func readsDisplayMath() {
        #expect(UnicodeMath.text("$$E = mc^2$$") == "E = mc²")
        #expect(UnicodeMath.text(#"\[\sum_{i=1}^{n} x_i\]"#) == "∑ᵢ₌₁ⁿ xᵢ")
    }

    @Test func writesScriptsWhereUnicodeHasThem() {
        #expect(UnicodeMath.expression("x^{10} + y_1") == "x¹⁰ + y₁")
        #expect(UnicodeMath.expression("90^\\circ") == "90°")
        #expect(UnicodeMath.expression("e^{i\\pi}") == "e^(iπ)")
        #expect(UnicodeMath.expression("x_{max}") == "xₘₐₓ")
        #expect(UnicodeMath.expression("x_{q}") == "x_q")
    }

    @Test func readsFractionsRootsAndText() {
        #expect(UnicodeMath.expression(#"\frac{a+b}{2}"#) == "(a+b)/2")
        #expect(UnicodeMath.expression(#"\sqrt{2}"#) == "√2")
        #expect(UnicodeMath.expression(#"\text{rate} = \mathbb{R}"#) == "rate = ℝ")
        #expect(UnicodeMath.expression(#"\left( x \right)"#) == "( x )")
    }

    @Test func leavesMoneyAndUnknownCommandsAlone() {
        #expect(UnicodeMath.text("$412 left and $30 spent") == "$412 left and $30 spent")
        #expect(UnicodeMath.text("costs $ 5 or $10") == "costs $ 5 or $10")
        #expect(UnicodeMath.text(#"\$5 \$6"#) == #"\$5 \$6"#)
        #expect(UnicodeMath.expression(#"\weird x"#) == #"\weird x"#)
        #expect(UnicodeMath.text(#"C:\Users"#) == #"C:\Users"#)
    }

    @Test func previewsTheFirstLineWithMathRead() {
        #expect(Agent.preview("**Done**: $a \\to b$\nmore") == "Done: a → b")
        #expect(Agent.preview("$$\n\\pi r^2\n$$") == "π r²")
    }
}

/// Single-dollar math by thaali's rule: only a span that reads as LaTeX is
/// math, so prices stay prices, and code is never touched.
struct MathDelimiterTests {
    @Test func moneyStaysMoney() {
        let prices = "That's $412 left, $5 and $10"
        #expect(UnicodeMath.text(prices) == prices)
        #expect(MathDelimiters.pieces(prices).allSatisfy { if case .math = $0 { false } else { true } })
        #expect(MathDelimiters.normalize(prices) == #"That's \$412 left, \$5 and \$10"#)
        #expect(MathDelimiters.normalize("$x$ costs $5") == #"\$x\$ costs \$5"#)
    }

    @Test func latexIsMath() {
        #expect(MathDelimiters.pieces(#"$\rightarrow$"#) == [.math(#"\rightarrow"#, .dollar)])
        #expect(MathDelimiters.pieces("$x^2$") == [.math("x^2", .dollar)])
        #expect(MathDelimiters.normalize(#"go $\rightarrow$ and $x^2$"#) == #"go \(\rightarrow\) and \(x^2\)"#)
        #expect(UnicodeMath.text(#"$\rightarrow$ and $x^2$"#) == "→ and x²")
    }

    @Test func dollarsTouchingWordsOrSpacesAreNotMath() {
        #expect(MathDelimiters.normalize("a$x_1$b") == #"a\$x_1\$b"#)
        #expect(MathDelimiters.normalize("$ x_1$") == #"\$ x_1\$"#)
        #expect(MathDelimiters.normalize("$x_1 $") == #"\$x_1 \$"#)
        #expect(MathDelimiters.normalize("$2^x$") == #"\$2^x\$"#)
    }

    @Test func otherDelimitersStayMath() {
        #expect(MathDelimiters.normalize(#"$$E = mc^2$$ and \(a\) and \[b\]"#) == #"$$E = mc^2$$ and \(a\) and \[b\]"#)
        #expect(MathDelimiters.pieces(#"\(5\)"#) == [.math("5", .parenthesis)])
    }

    @Test func codeIsLeftAsWritten() {
        #expect(MathDelimiters.normalize("run `echo $HOME_x^2$` now") == "run `echo $HOME_x^2$` now")
        let fenced = "```sh\nprice=$5\necho $x^2$\n```\nafter $5"
        #expect(MathDelimiters.normalize(fenced) == "```sh\nprice=$5\necho $x^2$\n```\nafter \\$5")
    }
}

/// Ghar's page arranges devices by room and tag, sums up what is on, and
/// reads each light's color from its state.
struct GharLayoutTests {
    private let bedroom = GharRoom(id: "r1", name: "Ankur's room")
    private let kitchen = GharRoom(id: "r2", name: "Kitchen")
    private let loose = GharRoom(id: "r0", name: "unassigned")

    private func light(_ id: String, _ name: String, room: GharRoom, on: Bool, brightness: Int = 80, mode: String = "color_temp", mireds: Int = 357, hue: Int = 0, saturation: Int = 0, tags: [String] = []) throws -> GharDevice {
        let json: [String: Any] = [
            "id": id, "name": name, "kind": "light", "product_name": "Smart RGBTW Bulb",
            "room": ["id": room.id, "name": room.name],
            "tags": tags.map { ["id": "t-\($0)", "name": $0] },
            "capabilities": [
                ["capability": "on_off", "config": [String: Any]()],
                ["capability": "level", "config": ["min": 0, "max": 100]],
                ["capability": "color", "config": ["modes": ["hue_sat", "color_temp"]]],
            ],
            "online": true,
            "state": [
                "on": ["value": on], "brightness": ["value": brightness], "color_mode": ["value": mode],
                "color_temp": ["value": mireds], "hue": ["value": hue], "saturation": ["value": saturation],
            ],
        ]
        return try ServiceJSON.decoder.decode(GharDevice.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func roomsComeByNameWithLooseDevicesLast() throws {
        let devices = [
            try light("a", "Right Nightstand", room: bedroom, on: false),
            try light("b", "Desk Lamp", room: bedroom, on: true),
            try light("c", "Hall", room: loose, on: false),
        ]
        let sections = GharLayout.sections(devices, rooms: [loose, kitchen, bedroom])
        #expect(sections.map(\.room.name) == ["Ankur's room", "Kitchen", "unassigned"])
        #expect(sections[0].devices.map(\.name) == ["Desk Lamp", "Right Nightstand"])
        #expect(sections[1].devices.isEmpty)
        #expect(sections.map(\.placed) == [true, true, false])
        #expect(GharLayout.whereabouts(sections) == "2 lights in Ankur's room, 1 not in a room")
        #expect(GharLayout.sections(Array(devices.prefix(2)), rooms: [loose, bedroom]).map(\.room.name) == ["Ankur's room"])
    }

    @Test func groupsCollectEveryDeviceWithTheTag() throws {
        let devices = [
            try light("a", "Right Nightstand", room: bedroom, on: false, tags: ["Nightstands"]),
            try light("b", "Left Nightstand", room: kitchen, on: true, tags: ["Nightstands", "Bedtime"]),
            try light("c", "Desk Lamp", room: bedroom, on: true),
        ]
        let groups = GharLayout.groups(devices)
        #expect(groups.map(\.name) == ["Bedtime", "Nightstands"])
        #expect(groups[1].devices.map(\.name) == ["Left Nightstand", "Right Nightstand"])
    }

    @Test func summaryCountsWhatIsOnAndItsBrightness() throws {
        let devices = [
            try light("a", "One", room: bedroom, on: true, brightness: 80),
            try light("b", "Two", room: bedroom, on: true, brightness: 40),
            try light("c", "Three", room: bedroom, on: false, brightness: 100),
        ]
        let summary = GharLayout.summary(devices)
        #expect(summary.on == 2 && summary.total == 3)
        #expect(summary.level == 60)
        #expect(summary.color != nil)
        #expect(GharLayout.headline(summary) == "2 of 3 lights on")
        #expect(GharLayout.status(summary) == "2 of 3 on")
        let off = GharLayout.summary([try light("c", "Three", room: bedroom, on: false)])
        #expect(off.level == nil && off.color == nil)
        #expect(GharLayout.status(off) == "All off")
    }

    @Test func colorComesFromTheLightsMode() throws {
        let warm = try light("a", "Warm", room: bedroom, on: true, mode: "color_temp", mireds: 357)
        let color = GharLayout.color(warm)
        #expect(color.red == 1 && color.green > color.blue && color.blue < 0.5)
        #expect(GharLayout.colorName(warm) == "Warm white")
        #expect(GharLayout.status(warm) == "80% · Warm white")

        let peach = try light("b", "Peach", room: bedroom, on: true, mode: "hue_sat", hue: 13, saturation: 124)
        let tint = GharLayout.color(peach)
        #expect(tint.red == 1 && tint.green > tint.blue && tint.blue > 0.4)
        #expect(GharLayout.colorName(peach) == "Peach")
        #expect(LightPreset.all.first { $0.name == "Peach" }?.matches(peach) == true)
        #expect(LightPreset.all.first { $0.name == "Warm white" }?.matches(peach) == false)
        #expect(GharLayout.colorNames([warm, peach, warm]) == "Warm white · peach")
    }

    @Test func daylightIsWhiteAndCandleIsOrange() {
        let day = LightColor.white(kelvin: 6500)
        #expect(day.blue > day.red && day.red > 0.8)
        let candle = LightColor.white(kelvin: 2000)
        #expect(candle.red == 1 && candle.blue < 0.1)
        #expect(LightColor.hue(0, saturation: 254) == LightColor(red: 1, green: 0, blue: 0))
        #expect(LightColor.hue(0, saturation: 0) == .white)
    }
}

/// Nas's Annex B stream becomes one config, then one length-prefixed frame
/// per delimiter, with key frames marked.
struct H264SplitterTests {
    private func annexB(_ nalus: [[UInt8]]) -> Data {
        Data(nalus.flatMap { [0, 0, 0, 1] + $0 })
    }

    @Test func splitsConfigAndFramesAcrossChunks() {
        let sps: [UInt8] = [0x67, 0x64, 0x00, 0x1f]
        let pps: [UInt8] = [0x68, 0xee, 0x3c]
        let idr: [UInt8] = [0x65, 0x88, 0x84]
        let delta: [UInt8] = [0x41, 0x9a]
        let delimiter: [UInt8] = [0x09, 0x10]
        let stream = annexB([delimiter, sps, pps, idr, delimiter, delta, delimiter, delimiter])
        var splitter = H264Splitter()
        var events: [H264Event] = []
        for start in stride(from: 0, to: stream.count, by: 5) {
            events += splitter.push(stream[start..<min(start + 5, stream.count)])
        }
        #expect(events == [
            .config(sps: Data(sps), pps: Data(pps)),
            .frame(H264Frame(key: true, data: Data([0, 0, 0, 3] + idr))),
            .frame(H264Frame(key: false, data: Data([0, 0, 0, 2] + delta))),
        ])
    }

    @Test func repeatedParameterSetsAreNotNewConfigs() {
        let sps: [UInt8] = [0x67, 0x64, 0x00, 0x1f]
        let pps: [UInt8] = [0x68, 0xee, 0x3c]
        var splitter = H264Splitter()
        let first = splitter.push(annexB([sps, pps, [0x09, 0x10]]))
        let again = splitter.push(annexB([sps, pps, [0x09, 0x10]]))
        #expect(first == [.config(sps: Data(sps), pps: Data(pps))])
        #expect(again.isEmpty)
    }
}

/// Log rows keep the agent's own payload keys, and group into wakes by the
/// wake id Hath stamps on them.
struct ActivityTests {
    private func logs(_ json: String) throws -> [LogRecord] {
        try ServiceJSON.verbatim.decode([LogRecord].self, from: Data(json.utf8))
    }

    private let rows = #"""
    [
      {"id":"1","agent_id":"a","lane":"conversation","event":"message","wake_id":"w1","created_at":"2026-10-23T10:00:00.000Z",
       "payload":{"direction":"receive","from_agent_id":null,"content":"hi"}},
      {"id":"2","agent_id":"a","lane":"conversation","event":"response","wake_id":"w1","created_at":"2026-10-23T10:00:01.000Z",
       "payload":{"stop_reason":"tool_use","content":[{"type":"thinking","thinking":"**Plan**\nlook it up"},{"type":"tool_use","id":"t1","name":"search","input":{"to_agent_id":"b"}}]}},
      {"id":"3","agent_id":"a","lane":"conversation","event":"tool_result","wake_id":"w1","created_at":"2026-10-23T10:00:02.000Z",
       "payload":{"tool_use_id":"t1","content":"boom","is_error":true}},
      {"id":"4","agent_id":"a","lane":"reasoning","event":"response","wake_id":"w2","created_at":"2026-10-23T11:00:00.000Z",
       "payload":{"stop_reason":"end_turn","content":[{"type":"text","text":"done"}]}}
    ]
    """#

    @Test func keepsPayloadKeysVerbatim() throws {
        let call = try #require(logs(rows)[1].payload["content"]?.array?.last?.object)
        #expect(call["input"]?.object?["to_agent_id"]?.string == "b")
    }

    @Test func groupsByWakeNewestFirstWithToolOutcomes() throws {
        let wakes = Activity.wakes(from: try logs(rows))
        #expect(wakes.map(\.key) == ["4", "1"])
        let first = wakes[1]
        #expect(first.toolCount == 1)
        #expect(first.errorCount == 1)
        guard case .turn(let turn) = first.steps[1], case .tool(_, let tool) = turn.parts[0] else {
            Issue.record("expected a tool step")
            return
        }
        #expect(tool.result == ToolOutcome(content: "boom", isError: true))
        #expect(turn.gist == "Plan")
    }

    @Test func keepsWakeKeysAsLogsSlide() throws {
        let all = Activity.wakes(from: try logs(rows))
        let slid = Activity.wakes(from: Array(try logs(rows).dropFirst()))
        #expect(Activity.carryKeys(from: all, to: slid).map(\.key) == ["4", "1"])
    }
}

/// A schedule edit sends only what changed, and "once" is an explicit null.
struct PatchScheduleTests {
    @Test func sendsOnlyChangesAndNullsAOneShot() throws {
        var request = PatchScheduleRequest()
        request.content = "later"
        request.repeats = .once
        let json = try JSONSerialization.jsonObject(with: ServiceJSON.encoder.encode(request)) as? [String: Any]
        #expect(json?["content"] as? String == "later")
        #expect(json?["interval_minutes"] is NSNull)
        #expect(json?["run_at"] == nil)
    }
}
