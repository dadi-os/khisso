import Foundation
import Testing
@testable import Khisso

private func fields(_ key: String, ctrl: Bool = false, shift: Bool = false, meta: Bool = false) -> KeyFields {
    KeyFields(key: key, ctrl: ctrl, meta: meta, shift: shift)
}

@Suite struct BrowserActivityTests {
    @Test func saysHeDidNothingWhenNothingWasRecorded() {
        #expect(BrowserActivityLog().summary() == "Ankur took over this browser but did nothing.")
    }

    @Test func countsClicksKeysAndCharactersAndNeverHoldsTheTextTyped() throws {
        var log = BrowserActivityLog()
        for _ in 0..<3 { log.record(.click) }
        log.record(.scroll)
        log.record(.scroll)
        for character in "hunter2-secret!!" { log.record(try #require(browserKeyActivity(fields(String(character))))) }
        log.record(.key("Back"))
        let summary = log.summary()
        #expect(summary == "Ankur took over this browser. He clicked 3 times, scrolled, typed 16 characters, and pressed Back once.")
        #expect(!summary.contains("hunter2"))
    }

    @Test func speaksInTheSingularAndNamesRepeatedKeys() {
        var log = BrowserActivityLog()
        log.record(.click)
        log.record(.type(chars: 1))
        log.record(.key("Enter"))
        log.record(.key("Enter"))
        #expect(log.summary() == "Ankur took over this browser. He clicked once, typed 1 character, and pressed Enter twice.")
    }

    @Test func startsFromNothingAfterAReset() {
        var log = BrowserActivityLog()
        log.record(.click)
        log.reset()
        #expect(log.summary() == "Ankur took over this browser but did nothing.")
    }

    @Test func typesPrintableKeysNamesChordsAndIgnoresAModifierAlone() {
        #expect(browserKeyActivity(fields("a")) == .type(chars: 1))
        #expect(browserKeyActivity(fields("Enter")) == .key("Enter"))
        #expect(browserKeyActivity(fields("a", ctrl: true)) == .key("Ctrl-A"))
        #expect(browserKeyActivity(fields("ArrowDown")) == .key("Down"))
        #expect(browserKeyActivity(fields("Tab", shift: true)) == .key("Shift-Tab"))
        #expect(browserKeyActivity(fields("Shift", shift: true)) == nil)
    }
}

@Suite struct TerminalActivityTests {
    @Test func saysHeTypedNothingWhenNothingWasRecorded() {
        #expect(TerminalActivityLog().summary() == "Ankur took over this terminal but typed nothing.")
    }

    @Test func listsTheCommandsHeRanSplitAtEnterVerbatim() {
        var log = TerminalActivityLog()
        log.record(.text("ls -la"))
        log.record(.enter)
        log.record(.text("cd ~/src"))
        log.record(.enter)
        #expect(log.summary() == "Ankur took over this terminal and ran: `ls -la`, `cd ~/src`.")
    }

    @Test func appliesBackspaceDropsALineAtCtrlCAndNamesKeysInOrder() {
        var log = TerminalActivityLog()
        log.record(.text("lss"))
        log.record(.backspace)
        log.record(.enter)
        log.record(.text("sleep 100"))
        log.record(.key("Ctrl-C"))
        log.record(.text("pwd"))
        log.record(.enter)
        #expect(log.summary() == "Ankur took over this terminal and ran: `ls`, Ctrl-C, `pwd`.")
    }

    @Test func splitsPastedTextAtNewlinesAndReportsTextLeftUnrun() {
        var log = TerminalActivityLog()
        log.record(.text("make\r\nmake test\npartial"))
        #expect(log.summary() == "Ankur took over this terminal and ran: `make`, `make test`, then typed `partial` without running it.")
    }

    @Test func recordsAnEnterOnAnEmptyLineAsTheKey() {
        var log = TerminalActivityLog()
        log.record(.key("Up"))
        log.record(.enter)
        #expect(log.summary() == "Ankur took over this terminal and ran: Up, Enter.")
    }

    @Test func cutsAVeryLongCommandAndCountsThePastTheListsEnd() {
        var log = TerminalActivityLog()
        log.record(.text("echo " + String(repeating: "x", count: 500)))
        log.record(.enter)
        #expect(log.summary().contains("`echo " + String(repeating: "x", count: 195) + "…`"))
        for index in 0..<40 {
            log.record(.text("c\(index)"))
            log.record(.enter)
        }
        let summary = log.summary()
        #expect(summary.contains("and 11 more"))
        #expect(!summary.contains("`c39`"))
    }

    @Test func startsFromNothingAfterAReset() {
        var log = TerminalActivityLog()
        log.record(.text("ls"))
        log.reset()
        #expect(log.summary() == "Ankur took over this terminal but typed nothing.")
    }

    @Test func namesAKeyTheWayTheSummariesReadIt() {
        #expect(keyName(fields("c", ctrl: true)) == "Ctrl-C")
        #expect(keyName(fields(" ")) == "Space")
    }
}

@Suite struct TerminalKeysTests {
    @Test func sendsPrintableCharactersAsLiteralTextAndCountsThemAsTyped() {
        #expect(terminalInput(of: fields("a")) == TerminalInput(batch: KeyBatch(keys: ["a"], literal: true), activity: .text("a")))
        #expect(terminalInput(of: fields(" "))?.batch == KeyBatch(keys: [" "], literal: true))
        #expect(terminalInput(of: fields("A", shift: true))?.batch == KeyBatch(keys: ["A"], literal: true))
    }

    @Test func mapsTheEditingAndCursorKeysToTmuxNames() {
        let names = ["Enter": "Enter", "Backspace": "BSpace", "Tab": "Tab", "Escape": "Escape", "ArrowUp": "Up", "ArrowDown": "Down", "ArrowLeft": "Left", "ArrowRight": "Right", "Home": "Home", "End": "End", "PageUp": "PPage", "PageDown": "NPage", "Delete": "DC"]
        for (pressed, sent) in names {
            #expect(terminalInput(of: fields(pressed))?.batch == KeyBatch(keys: [sent], literal: false))
        }
        #expect(terminalInput(of: fields("Tab", shift: true))?.batch == KeyBatch(keys: ["BTab"], literal: false))
    }

    @Test func mapsCtrlWithALetterToAChordAndNamesItInTheSummary() {
        #expect(terminalInput(of: fields("c", ctrl: true)) == TerminalInput(batch: KeyBatch(keys: ["C-c"], literal: false), activity: .key("Ctrl-C")))
        #expect(terminalInput(of: fields("D", ctrl: true))?.batch.keys == ["C-d"])
    }

    @Test func feedsTheSummaryEnterBackspaceAndNamedKeysAndNothingForCursorMoves() {
        #expect(terminalInput(of: fields("Enter"))?.activity == .enter)
        #expect(terminalInput(of: fields("Backspace"))?.activity == .backspace)
        #expect(terminalInput(of: fields("ArrowUp"))?.activity == .key("Up"))
        #expect(terminalInput(of: fields("ArrowLeft"))?.activity == nil)
    }

    @Test func leavesCmdChordsOtherCtrlChordsAndModifiersAlone() {
        #expect(terminalInput(of: fields("v", meta: true)) == nil)
        #expect(terminalInput(of: fields("[", ctrl: true)) == nil)
        #expect(terminalInput(of: fields("Shift", shift: true)) == nil)
        #expect(terminalInput(of: fields("F5")) == nil)
    }

    @Test func sendsPastedTextLiterallyWithItsNewlines() {
        #expect(terminalPaste(of: "ls\nls -la") == TerminalInput(batch: KeyBatch(keys: ["ls\nls -la"], literal: true), activity: .text("ls\nls -la")))
        #expect(terminalPaste(of: "") == nil)
    }
}

/// Sends that the test releases one at a time, recording what was sent.
@MainActor
private final class HeldSends {
    var sent: [KeyBatch] = []
    var errors: [String] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    var fail = false

    func send(_ keys: [String], _ literal: Bool) async throws {
        sent.append(KeyBatch(keys: keys, literal: literal))
        await withCheckedContinuation { waiting.append($0) }
        if fail { throw URLError(.notConnectedToInternet) }
    }

    func release() async {
        for _ in 0..<5 { await Task.yield() }
        while !waiting.isEmpty { waiting.removeFirst().resume(); for _ in 0..<5 { await Task.yield() } }
    }
}

@MainActor @Suite struct KeySenderTests {
    @Test func sendsAtOnceWhenIdleThenJoinsWhatQueuedBehindTheRequestInFlight() async {
        let held = HeldSends()
        let sender = KeySender(send: held.send, onError: { held.errors.append($0.localizedDescription) })
        sender.push(KeyBatch(keys: ["l"], literal: true))
        for _ in 0..<5 { await Task.yield() }
        sender.push(KeyBatch(keys: ["s"], literal: true))
        sender.push(KeyBatch(keys: [" "], literal: true))
        sender.push(KeyBatch(keys: ["Enter"], literal: false))
        sender.push(KeyBatch(keys: ["Up"], literal: false))
        await held.release()
        #expect(held.sent == [KeyBatch(keys: ["l"], literal: true), KeyBatch(keys: ["s "], literal: true), KeyBatch(keys: ["Enter", "Up"], literal: false)])
        #expect(held.errors.isEmpty)
    }

    @Test func dropsAFailedBatchAndReportsItWithoutRetrying() async {
        let held = HeldSends()
        held.fail = true
        let sender = KeySender(send: held.send, onError: { held.errors.append($0.localizedDescription) })
        sender.push(KeyBatch(keys: ["x"], literal: true))
        await held.release()
        #expect(held.sent.count == 1)
        #expect(held.errors.count == 1)
    }
}

@MainActor @Suite struct TakeoverControlTests {
    /// A control over fake Nas calls that record what they were given.
    private final class Calls {
        var log: [String] = []
        var failPause = false
        var failResume = false
    }

    private func setup(isBrowser: Bool = true, idle: Duration = idleReturn) -> (TakeoverControl, Calls) {
        let calls = Calls()
        let control = TakeoverControl(
            isBrowser: isBrowser,
            idle: idle,
            pause: {
                calls.log.append("pause")
                if calls.failPause { throw URLError(.notConnectedToInternet) }
            },
            resume: { summary in
                calls.log.append("resume: \(summary)")
                if calls.failResume { throw URLError(.notConnectedToInternet) }
            }
        )
        return (control, calls)
    }

    @Test func handsBackBeforeNasAbandonsTheTaskAt30Minutes() {
        #expect(idleReturn == .seconds(29 * 60))
    }

    @Test func watchesAtFirstInputIsDroppedNothingPausesAndAHandBackDoesNothing() async {
        let (control, calls) = setup()
        #expect(control.state == .watching)
        #expect(control.record(BrowserActivity.click) == false)
        #expect(await control.handBack())
        #expect(calls.log.isEmpty)
    }

    @Test func pausesAtTakeoverAndLetsInputThroughFromThen() async {
        let (control, calls) = setup()
        await control.takeOver()
        #expect(calls.log == ["pause"])
        #expect(control.state == .inControl)
        #expect(control.record(BrowserActivity.click))
    }

    @Test func staysWatchingAndSaysSoWhenThePauseFails() async {
        let (control, calls) = setup()
        calls.failPause = true
        await control.takeOver()
        #expect(control.state == .watching)
        #expect(control.problem?.hasPrefix("The task did not pause") == true)
        #expect(control.record(BrowserActivity.click) == false)
    }

    @Test func returnsTheTaskWithASummaryGoesBackToWatchingAndStartsFreshAtTheNextTakeover() async {
        let (control, calls) = setup()
        await control.takeOver()
        _ = control.record(BrowserActivity.click)
        _ = control.record(BrowserActivity.click)
        #expect(await control.handBack())
        #expect(control.state == .watching)
        #expect(calls.log[1] == "resume: Ankur took over this browser. He clicked twice.")
        #expect(control.record(BrowserActivity.click) == false)
        await control.takeOver()
        _ = await control.handBack()
        #expect(calls.log[3] == "resume: Ankur took over this browser but did nothing.")
    }

    @Test func aTerminalHandsBackItsCommands() async {
        let (control, calls) = setup(isBrowser: false)
        await control.takeOver()
        _ = control.record(TerminalActivity.text("ls -la"))
        _ = control.record(TerminalActivity.enter)
        _ = control.record(TerminalActivity.key("Ctrl-C"))
        _ = await control.handBack()
        #expect(calls.log[1] == "resume: Ankur took over this terminal and ran: `ls -la`, Ctrl-C.")
    }

    @Test func keepsHimInControlAndSaysSoWhenTheHandBackFailsSoClosingCanBeRetried() async {
        let (control, calls) = setup()
        await control.takeOver()
        calls.failResume = true
        #expect(await control.handBack() == false)
        #expect(control.state == .inControl)
        #expect(control.problem?.hasPrefix("The task did not resume") == true)
        calls.failResume = false
        #expect(await control.handBack())
        #expect(control.problem == nil)
    }

    @Test func handsBackByItselfWithTheSummaryAfterTheIdleWaitAndInputRestartsTheWait() async throws {
        let (control, calls) = setup(idle: .milliseconds(400))
        await control.takeOver()
        try await Task.sleep(for: .milliseconds(250))
        _ = control.record(BrowserActivity.scroll)
        try await Task.sleep(for: .milliseconds(250))
        #expect(control.state == .inControl)
        try await Task.sleep(for: .milliseconds(450))
        #expect(control.state == .watching)
        #expect(calls.log.last == "resume: Ankur took over this browser. He scrolled.")
    }

    @Test func stopsWaitingAndHandingBackOnceDisposed() async throws {
        let (control, calls) = setup(idle: .milliseconds(100))
        await control.takeOver()
        control.dispose()
        try await Task.sleep(for: .milliseconds(300))
        _ = await control.handBack()
        #expect(calls.log == ["pause"])
    }
}

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

    @Test func skipsATaskThatIsAsleepStoppedOrHoldsNothing() throws {
        let pins = PinnedTasks(of: [
            try task("browser", "a", status: "asleep", resource: nil, at: "2026-11-09T10:00:00Z"),
            try task("browser", "b", status: "stopped", at: "2026-11-09T10:00:00Z"),
            try task("terminal", "c", status: "asleep", resource: nil, at: "2026-11-09T10:00:00Z"),
        ])
        #expect(pins.isEmpty)
    }
}
