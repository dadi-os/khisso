import Foundation
import Testing
@testable import Khisso

/// The day's due items and the Due panel's rules.
@Suite struct DueAxisTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Detroit")!
        return c
    }()

    private func item(_ id: String, due: String?, start: String? = nil, hidden: Bool = false) -> TimelineItem {
        func date(_ time: String) -> Date { try! Date("2026-10-21T\(time):00-04:00", strategy: .iso8601) }
        return TimelineItem(
            planId: id, occurrenceDate: "2026-10-21", title: id, body: nil, kind: .task, status: .confirmed,
            startAt: start.map(date), endAt: start.map(date), dueAt: due.map(date), opensAt: nil, allDay: false, timeZone: nil, hideFromPlanner: hidden,
            state: "scheduled", outcome: nil, recurrence: nil, series: nil, place: nil, owner: "schedule-specialist", notes: []
        )
    }

    private var day: Date { try! Date("2026-10-21T12:00:00-04:00", strategy: .iso8601) }

    @Test func onlyUntimedItemsDueThatDayAreDueItems() {
        let kept = PlannerLayout.dues([
            item("due", due: "09:00"),
            item("timed", due: "09:00", start: "08:00"),
            item("hidden", due: "09:00", hidden: true),
            item("none", due: nil),
        ], on: day, calendar: calendar)
        #expect(kept.map(\.planId) == ["due"])
    }

    @Test func dueItemsDoNotWidenTheAxis() {
        #expect(PlannerLayout.hours([]) == PlannerLayout.emptyHours)
    }

    @Test func theDuePanelListsDueItemsInTimeOrderKeepingTiesInInputOrder() {
        let ordered = DueList.ordered([item("b", due: "15:00"), item("a", due: "09:00"), item("c", due: "15:00")])
        #expect(ordered.map(\.planId) == ["a", "b", "c"])
    }

    @Test func theDuePanelGrowsToItsRowsThenStopsAtAThirdOfThePage() {
        #expect(DueList.height(content: 100, available: 900) == 100)
        #expect(DueList.height(content: 900, available: 900) == 300)
    }

    @Test func urgencyIsOverdueOnceTimePassedSoonWithinTwoHoursElseLater() {
        let now = try! Date("2026-10-21T10:00:00-04:00", strategy: .iso8601)
        #expect(DueList.urgency(item("x", due: "09:59"), now: now) == .overdue)
        #expect(DueList.urgency(item("x", due: "11:59"), now: now) == .soon)
        #expect(DueList.urgency(item("x", due: "12:01"), now: now) == .later)
    }

    @Test func aCompletedItemIsNeverPressing() {
        let now = try! Date("2026-10-21T10:00:00-04:00", strategy: .iso8601)
        let done = item("x", due: "09:00").marked(completed: true)
        #expect(DueList.urgency(done, now: now) == .later)
    }
}

/// Chats lists conversations by day, with a dot while an agent runs.
@Suite struct ChatGroupsTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Detroit")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    private let now = try! Date("2026-11-09T15:00:00-05:00", strategy: .iso8601)

    private func thread(_ id: String, at: String, unread: Int = 0) throws -> ThreadSummary {
        let body = #"{"agent_id":"\#(id)","agent_name":"\#(id)","last_message":"hi","last_at":"\#(at)","from_user":false,"unread":\#(unread),"read_seq":null}"#
        return try ServiceJSON.decoder.decode(ThreadSummary.self, from: Data(body.utf8))
    }

    @Test func headsDaysAsTodayYesterdayThenTheDate() throws {
        func label(_ iso: String) throws -> String { ChatGroups.dayLabel(try Date(iso, strategy: .iso8601), now: now, calendar: calendar) }
        #expect(try label("2026-11-09T01:00:00-05:00") == "Today")
        #expect(try label("2026-11-08T23:59:00-05:00") == "Yesterday")
        #expect(try label("2026-11-05T12:00:00-05:00") == "Thu, Nov 5")
    }

    @Test func groupsConversationsByDayInOrderAndFiltersByName() throws {
        let threads = [
            try thread("alpha", at: "2026-11-09T14:00:00-05:00"),
            try thread("beta", at: "2026-11-09T09:00:00-05:00"),
            try thread("gamma", at: "2026-11-08T20:00:00-05:00"),
            try thread("alpine", at: "2026-11-02T10:00:00-05:00"),
        ]
        let days = ChatGroups.days(threads, matching: "", now: now, calendar: calendar)
        #expect(days.map(\.label) == ["Today", "Yesterday", "Mon, Nov 2"])
        #expect(days[0].threads.map(\.agentId) == ["alpha", "beta"])
        let found = ChatGroups.days(threads, matching: " ALP ", now: now, calendar: calendar)
        #expect(found.map(\.label) == ["Today", "Mon, Nov 2"])
        #expect(ChatGroups.days(threads, matching: "zzz", now: now, calendar: calendar).isEmpty)
    }

    @Test func aRowDotsWhileEitherLaneRuns() {
        #expect(!ChatGroups.isWorking([]))
        #expect(ChatGroups.isWorking([.work]))
        #expect(ChatGroups.isWorking([.process]))
    }

    @Test func showsTheTimeTodayThenTheDay() throws {
        #expect(ChatGroups.when(try Date("2026-11-08T20:00:00-05:00", strategy: .iso8601), now: now, calendar: calendar) == "Yesterday")
        #expect(ChatGroups.when(try Date("2026-11-09T14:05:00-05:00", strategy: .iso8601), now: now, calendar: calendar).contains("2:05"))
    }
}

/// A thread's composer follows the condensed dock.
@Suite struct ThreadDockTests {
    @Test func theComposerShowsUnlessTheDockIsCondensedAndNobodyIsWriting() {
        #expect(ThreadDock.showsComposer(condensed: false, writing: false))
        #expect(!ThreadDock.showsComposer(condensed: true, writing: false))
        #expect(ThreadDock.showsComposer(condensed: true, writing: true))
    }

    @MainActor @Test func expandingTheDockEndsWritingFromTheCondensedOne() {
        let dock = ThreadDock()
        dock.condense(true)
        dock.writing = true
        #expect(dock.composerShown)
        dock.condense(false)
        #expect(!dock.writing && dock.composerShown)
        dock.condense(true)
        #expect(!dock.composerShown)
    }
}

/// The Needs a time sheet opens over the shown view, and the thread's status pill stays large.
@Suite struct NeedsTimeAndPillTests {
    @Test func needsATimeIsASheetNotAViewSoOpeningItLeavesTheDayAlone() {
        #expect(TimelineMode.allCases == [.day, .week, .month])
        #expect(!TimelineMode.allCases.map(\.rawValue).contains(TimelineMode.needsTimeTitle))
    }

    @Test func theThreadStatusPillKeepsAFingerSizedHeightAndTheChatsDotStaysSmall() {
        #expect(LaneChip.height >= 44)
        #expect(WorkingDot.size == 8)
    }
}
