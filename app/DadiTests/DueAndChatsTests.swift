import Foundation
import Testing
@testable import Khisso

/// Due items in the day's lane: which share a pill, as in thaali's `dueClusters.test.ts`.
@Suite struct DueClustersTests {
    private func group(_ ys: [CGFloat]) -> [[Int]] {
        DueClusters.group(ys.enumerated().map { (item: $0.offset, y: $0.element) }).map(\.items)
    }

    @Test func spreadItemsEachGetATag() {
        #expect(group([0, 28, 56]) == [[0], [1], [2]])
    }

    @Test func anItemLessThanOneTagAndGapBelowTheFirstJoinsIt() {
        #expect(group([100, 127.9]) == [[0, 1]])
        #expect(group([100, 128]) == [[0], [1]])
    }

    @Test func theGapIsMeasuredFromTheClustersFirstItemNotItsLast() {
        #expect(group([0, 20, 40]) == [[0, 1], [2]])
    }

    @Test func sameMinuteAlwaysClustersAndKeepsInputOrder() {
        #expect(group([50, 50, 50]) == [[0, 1, 2]])
        #expect(group([50, 10, 50]) == [[1], [0, 2]])
    }

    @Test func clustersSitAtTheirFirstMembersPosition() {
        let clusters = DueClusters.group([(item: "b", y: 40), (item: "a", y: 30), (item: "c", y: 200)])
        #expect(clusters.map(\.y) == [30, 200])
        #expect(clusters.map(\.items) == [["a", "b"], ["c"]])
    }

    @Test func noItemsMakeNoClusters() {
        let none: [(item: Int, y: CGFloat)] = []
        #expect(DueClusters.group(none).isEmpty)
    }
}

/// The planner's axis with due items on it.
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

    @Test func theAxisReachesAnHourEitherSideOfADueTime() {
        #expect(PlannerLayout.hours([], dueMinutes: [0]) == 0..<1)
        #expect(PlannerLayout.hours([], dueMinutes: [9 * 60]) == 8..<10)
        #expect(PlannerLayout.hours([], dueMinutes: [23 * 60 + 59]) == 22..<24)
        #expect(PlannerLayout.hours([], dueMinutes: []) == PlannerLayout.emptyHours)
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

/// Which sessions leave room for the due lane, as in thaali's `sessionsNeedingRoom` tests.
@Suite struct SessionRoomTests {
    private let tag = DueClusters.Extent(top: -12, bottom: 12)
    private func hour(_ h: CGFloat, length: CGFloat = 56) -> DueClusters.Extent {
        DueClusters.Extent(top: h * 56, bottom: h * 56 + length)
    }

    @Test func noDueTagInsetsNothing() {
        #expect(DueClusters.sessionsNeedingRoom([hour(0), hour(5)], tags: []) == [false, false])
    }

    @Test func aTagAtMidnightInsetsOnlySessionsNearIt() {
        #expect(DueClusters.sessionsNeedingRoom([hour(0), hour(2), hour(6)], tags: [tag]) == [true, false, false])
    }

    @Test func theMarginCountsButNotBeyondIt() {
        #expect(DueClusters.sessionsNeedingRoom([.init(top: 15, bottom: 60)], tags: [tag]) == [true])
        #expect(DueClusters.sessionsNeedingRoom([.init(top: 16, bottom: 60)], tags: [tag]) == [false])
    }

    @Test func aClusterPillsWholeExtentCounts() {
        let pill = DueClusters.Extent(top: 100, bottom: 148)
        #expect(DueClusters.sessionsNeedingRoom([.init(top: 140, bottom: 200), .init(top: 300, bottom: 360)], tags: [pill]) == [true, false])
    }

    @Test func anOverlappingGroupInsetsTogetherButNotTheNextGroup() {
        let sessions = [DueClusters.Extent(top: 0, bottom: 56), .init(top: 40, bottom: 200), .init(top: 300, bottom: 360)]
        #expect(DueClusters.sessionsNeedingRoom(sessions, tags: [.init(top: 0, bottom: 24)]) == [true, true, false])
    }
}
