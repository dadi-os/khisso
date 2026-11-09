import Foundation
import Testing
@testable import Khisso

@Suite struct PinnedTasksTests {
    private func task(_ kind: String, _ id: String, status: String = "working", resource: String? = "1", at: String, url: String? = nil) throws -> NasTask {
        let active = url.map { #","active_url":"\#($0)""# } ?? ""
        let json = #"{"task":"task/\#(kind)/\#(id)","kind":"\#(kind)","owner":"a","purpose":"p","status":"\#(status)","resource":\#(resource.map { "\"\($0)\"" } ?? "null"),"state":"s","last_activity":"\#(at)"\#(active)}"#
        return try ServiceJSON.decoder.decode(NasTask.self, from: Data(json.utf8))
    }

    @Test func readsTheActivePageAddressFromTheTask() throws {
        #expect(try task("browser", "1", at: "2026-11-09T10:00:00Z", url: "https://example.com/a").activeUrl == "https://example.com/a")
        #expect(try task("browser", "1", at: "2026-11-09T10:00:00Z").activeUrl == nil)
    }

    @Test func showsOnlyTheAddressWithoutItsSchemeOrALoneTrailingSlash() {
        #expect(PinnedTasks.pageAddress("https://canvas.msu.edu/") == "canvas.msu.edu")
        #expect(PinnedTasks.pageAddress("HTTP://a.dev/x/y") == "a.dev/x/y")
        #expect(PinnedTasks.pageAddress("https://a.dev//") == "a.dev/")
        #expect(PinnedTasks.pageAddress(nil) == "")
    }

    @Test func pinsTheNewestLiveBrowserAndTheNewestLiveTerminal() throws {
        let pins = PinnedTasks(of: [
            try task("browser", "old", at: "2026-11-09T09:00:00Z"),
            try task("browser", "new", at: "2026-11-09T10:00:00Z"),
            try task("terminal", "t1", resource: "t1", at: "2026-11-09T08:00:00Z"),
            try task("terminal", "t2", resource: "t2", at: "2026-11-09T11:00:00Z"),
        ])
        #expect(pins.browser?.id == "task/browser/new")
        #expect(pins.terminal?.id == "task/terminal/t2")
    }

    @Test func skipsATaskThatIsIdleAsleepStoppedOrHoldsNothing() throws {
        let pins = PinnedTasks(of: [
            try task("browser", "i", status: "idle", at: "2026-11-09T10:00:00Z"),
            try task("terminal", "d", status: "idle", resource: "d", at: "2026-11-09T10:00:00Z"),
            try task("browser", "a", status: "asleep", resource: nil, at: "2026-11-09T10:00:00Z"),
            try task("browser", "b", status: "stopped", at: "2026-11-09T10:00:00Z"),
            try task("terminal", "c", status: "asleep", resource: nil, at: "2026-11-09T10:00:00Z"),
        ])
        #expect(pins.isEmpty)
    }
}
