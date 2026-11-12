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
            startAt: start.map(date), endAt: start.map(date), dueAt: due.map(date), opensAt: nil, allDay: false, hideFromPlanner: hidden,
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

/// The dock's one composer: who it is for and what a thread's draft keeps.
@Suite struct DockComposerTests {
    @Test func theAccessoryIsDadiOnEveryPageButAThread() {
        #expect(DockDestination.of(openThread: nil, routerComposing: false) == .dadi)
        #expect(DockDestination.of(openThread: "career", routerComposing: false) == .thread(agentId: "career"))
    }

    @Test func dadisComposerOverAThreadTakesTheAccessoryFromTheThreadField() {
        #expect(DockDestination.of(openThread: "career", routerComposing: true) == .dadi)
        #expect(DockDestination.of(openThread: nil, routerComposing: true) == .dadi)
    }

    @Test func aDraftSendsWithWordsOrPhotosAndNotWhileOneIsGoing() {
        #expect(!ThreadDraft.canSend(text: "  \n", photos: 0, sending: false))
        #expect(ThreadDraft.canSend(text: "hi", photos: 0, sending: false))
        #expect(ThreadDraft.canSend(text: "", photos: 1, sending: false))
        #expect(!ThreadDraft.canSend(text: "hi", photos: 0, sending: true))
    }

    @MainActor @Test func eachAgentKeepsItsOwnDraftAcrossVisits() {
        let drafts = ThreadDrafts()
        drafts.draft(for: "career").text = "half a thought"
        #expect(drafts.draft(for: "career").text == "half a thought")
        #expect(drafts.draft(for: "health").text.isEmpty)
    }

    @MainActor @Test func quotingAMessageAsksTheFieldForTheCursor() throws {
        let draft = ThreadDraft()
        let before = draft.focusRequests
        let json = #"{"seq":4,"from_agent_id":"career","to_agent_id":null,"content":"hello","attachments":[],"created_at":"2026-11-09T10:00:00.000Z"}"#
        draft.reply(to: try ServiceJSON.decoder.decode(DurableMessage.self, from: Data(json.utf8)))
        #expect(draft.quote?.seq == 4)
        #expect(draft.focusRequests == before + 1)
    }
}

/// The Needs a time sheet opens over the shown view, and the thread's status pill stays large.
@Suite struct NeedsTimeAndPillTests {
    @Test func needsATimeIsASheetNotAViewSoOpeningItLeavesTheDayAlone() {
        #expect(TimelineMode.allCases == [.day, .week, .month])
        #expect(!TimelineMode.allCases.map(\.rawValue).contains(TimelineMode.needsTimeTitle))
    }

    @Test func theThreadStatusPillIsAModestStepAboveItsOriginal36() {
        #expect((39...42).contains(LaneChip.height))
        #expect(WorkingDot.size == 8)
    }
}

/// The week strip pages by weeks and keeps the weekday; asleep tasks are inert.
@Suite struct WeekStripAndTaskTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    @Test func pagingToAnotherWeekKeepsTheSelectedWeekday() throws {
        let wednesday = try Date("2026-11-11T15:00:00Z", strategy: .iso8601)
        let nextMonday = try Date("2026-11-16T00:00:00Z", strategy: .iso8601)
        let next = try #require(WeekStrip.day(in: nextMonday, keeping: wednesday, calendar: calendar))
        #expect(next == (try Date("2026-11-18T00:00:00Z", strategy: .iso8601)))
    }

    @Test func theStripReachesWeeksEitherSideOfThisOne() throws {
        let now = try Date("2026-11-11T15:00:00Z", strategy: .iso8601)
        let weeks = WeekStrip.weeks(around: now, calendar: calendar)
        #expect(weeks.count == 2 * WeekStrip.reach + 1)
        #expect(weeks[WeekStrip.reach] == (try Date("2026-11-09T00:00:00Z", strategy: .iso8601)))
    }

    @Test func anAsleepTaskDoesNotOpenItsCard() {
        #expect(!TaskRow.opens("asleep"))
        #expect(TaskRow.opens("idle") && TaskRow.opens("working") && TaskRow.opens("stopped"))
    }
}
