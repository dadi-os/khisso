import Foundation
import Testing
@testable import Khisso

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

    @Test func showsTheTimeTodayThenTheDay() throws {
        #expect(ChatGroups.when(try Date("2026-11-08T20:00:00-05:00", strategy: .iso8601), now: now, calendar: calendar) == "Yesterday")
        #expect(ChatGroups.when(try Date("2026-11-09T14:05:00-05:00", strategy: .iso8601), now: now, calendar: calendar).contains("2:05"))
    }
}

/// The dock's one composer: who it is for and what a thread's draft keeps.
@Suite struct DockComposerTests {
    @Test func theDadiBarShowsOnEveryRootPageIncludingChats() {
        for page in [HomeView.Page.dadi, .planner, .ghar, .chaavi, .system] {
            #expect(DockPresentation.of(page: page) == .dadi)
        }
    }

    @Test func anOpenThreadPutsItsOwnComposerInTheDockAccessory() {
        #expect(DockPresentation.of(page: .thread("career")) == .thread("career"))
        #expect(DockPresentation.of(page: .thread("health")) != .thread("career"))
    }

    @Test func aDraftSendsWithWordsOrFilesAndNotWhileOneIsGoing() {
        #expect(!ThreadDraft.canSend(text: "  \n", files: 0, sending: false))
        #expect(ThreadDraft.canSend(text: "hi", files: 0, sending: false))
        #expect(ThreadDraft.canSend(text: "", files: 1, sending: false))
        #expect(!ThreadDraft.canSend(text: "hi", files: 0, sending: true))
    }

    @MainActor @Test func eachAgentKeepsItsOwnDraftAcrossVisits() {
        let drafts = ThreadDrafts()
        drafts.draft(for: "career").text = "half a thought"
        #expect(drafts.draft(for: "career").text == "half a thought")
        #expect(drafts.draft(for: "health").text.isEmpty)
    }

    @MainActor @Test func quotingAMessageKeepsItWithThatAgentsDraft() throws {
        let draft = ThreadDraft()
        #expect(draft.quote == nil)
        let json = #"{"seq":4,"from_agent_id":"career","to_agent_id":null,"content":"hello","created_at":"2026-11-09T10:00:00.000Z"}"#
        draft.reply(to: try ServiceJSON.decoder.decode(DurableMessage.self, from: Data(json.utf8)))
        #expect(draft.quote?.seq == 4)
    }
}

/// Someday opens over the Day view, and the thread's status pill stays large.
@Suite struct SomedayAndPillTests {
    @Test func somedayIsNotAViewSoOpeningItLeavesTheViewsAlone() {
        #expect(PlannerMode.allCases == [.day, .month])
        #expect(PlannerMode(rawValue: "Week") == nil)
        #expect(!PlannerMode.allCases.map(\.rawValue).contains("Someday"))
    }

    @Test func theThreadStatusPillIsAModestStepAboveItsOriginal36() {
        #expect((39...42).contains(ActivityPill.height))
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

/// The dock's one re-select rule: a sub-state goes back to its tab's root.
@Suite struct TabReselectTests {
    @MainActor @Test func aThreadGoesBackToTheChatsListAndRootsStay() {
        #expect(TabReselect.root(for: .thread("a")) == .dadi)
        for page in [HomeView.Page.dadi, .planner, .ghar, .chaavi, .system] { #expect(TabReselect.root(for: page) == nil) }
    }

    @MainActor @Test func everyTabHasASlotInTheDock() {
        #expect(TabReselect.order.count == 5 && Set(TabReselect.order).count == 5)
        let reselect = TabReselect()
        reselect.fire(.chaavi)
        #expect(reselect.tick == 1 && reselect.tab == .chaavi)
    }

    @MainActor @Test func everyTabResetsItsSubStateBeforeItScrolls() {
        #expect(TabReselect.reset(tab: .dadi, page: .thread("a"), inSubState: false) == .chatsList)
        #expect(TabReselect.reset(tab: .dadi, page: .dadi, inSubState: false) == .none)
        #expect(TabReselect.reset(tab: .chaavi, page: .chaavi, inSubState: true) == .chaaviEverything)
        #expect(TabReselect.reset(tab: .ghar, page: .ghar, inSubState: true) == .gharEverywhere)
        #expect(TabReselect.reset(tab: .system, page: .system, inSubState: true) == .systemOverview)
        for tab in TabReselect.order { #expect(TabReselect.reset(tab: tab, page: tab.home, inSubState: false) == .none) }
        #expect(TabReselect.reset(tab: .planner, page: .planner, inSubState: true) == .none)
    }
}

/// The Chats tab's stack follows Home's page, and the drawer's filters are true counts of the list.
@Suite struct ChatsNavigationTests {
    @Test func aThreadIsOneAgentPushedOnTheListAndTheListIsAnEmptyStack() {
        #expect(ChatsRoute.path(for: .thread("career")) == ["career"])
        #expect(ChatsRoute.path(for: .dadi).isEmpty)
        #expect(ChatsRoute.page(for: ["career"]) == .thread("career"))
        #expect(ChatsRoute.page(for: []) == .dadi)
    }

    @MainActor @Test func aReselectPopsTheStackTheSameWayABackSwipeDoes() {
        let reset = TabReselect.reset(tab: .dadi, page: .thread("career"), inSubState: false)
        #expect(reset == .chatsList)
        #expect(ChatsRoute.path(for: TabReselect.root(for: .thread("career")) ?? .dadi).isEmpty)
    }

    private func thread(_ id: String, unread: Int) throws -> ThreadSummary {
        let body = #"{"agent_id":"\#(id)","agent_name":"\#(id)","last_message":"hi","last_at":"2026-11-09T14:00:00-05:00","from_user":false,"unread":\#(unread),"read_seq":null}"#
        return try ServiceJSON.decoder.decode(ThreadSummary.self, from: Data(body.utf8))
    }

    @Test func eachFilterCountsExactlyTheChatsItKeeps() throws {
        let threads = [try thread("a", unread: 2), try thread("b", unread: 0), try thread("c", unread: 0), try thread("d", unread: 1)]
        let states: [String: AgentState] = ["a": .working, "b": .waiting, "c": .idle, "d": .idle]
        let state = { states[$0] ?? .idle }
        #expect(ChatGroups.Filter.all.count(in: threads, state: state) == 4)
        #expect(ChatGroups.Filter.unread.count(in: threads, state: state) == 2)
        #expect(ChatGroups.Filter.working.count(in: threads, state: state) == 1)
        #expect(ChatGroups.Filter.waiting.count(in: threads, state: state) == 1)
        #expect(ChatGroups.Filter.idle.count(in: threads, state: state) == 2)
        #expect(threads.filter { ChatGroups.Filter.unread.keeps($0, state: state($0.agentId)) }.map(\.agentId) == ["a", "d"])
    }
}
