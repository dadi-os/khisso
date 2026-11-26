import Foundation
import Testing
@testable import Khisso

/// Builds plans and tasks on 2026-11-15 in Detroit, so every suite reads the same day.
private enum Day {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Detroit")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    static func at(_ time: String, _ date: String = "2026-11-15") -> Date {
        try! Date("\(date)T\(time):00-05:00", strategy: .iso8601)
    }

    static var noon: Date { at("12:00") }

    /// Local midnight of `date` (YYYY-MM-DD) in Detroit, right on either side of the November fall back.
    static func midnight(_ date: String) -> Date {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    static func plan(_ id: String, _ start: String, _ end: String?, rsvp: Rsvp? = nil, allDay: Bool = false, hub: Hub? = nil, owner: String = "schedule-specialist", attended: Bool? = nil, date: String = "2026-11-15", title: String? = nil) -> Plan {
        Plan(id: id, title: title ?? id, body: nil, rsvp: rsvp, startAt: at(start, date), endAt: end.map { at($0, date) }, allDay: allDay, timeZone: nil, attended: attended, place: nil, hub: hub, owner: owner, notes: [])
    }

    static func task(_ id: String, title: String? = nil, opens: String? = "2026-11-10", closes: Date? = nil, done: Bool = false, pastDue: Bool = false, verified: Date? = nil, owner: String = "efficiency-specialist") -> PlanTask {
        PlanTask(id: id, title: title ?? id, body: nil, opensOn: opens, closesAt: closes, done: done, verifiedAt: verified, createdAt: at("08:00", "2026-11-01"), updatedAt: at("08:00", "2026-11-01"), pastDue: pastDue, hub: nil, owner: owner)
    }
}

/// The Day grid lays plans out as thaali does: lanes for overlaps, free time between plans that are not declined.
struct PlannerLayoutTests {
    private let calendar = Day.calendar

    @Test func overlapsGetSideBySideLanes() {
        let segments = PlannerLayout.segments([Day.plan("a", "09:00", "10:00"), Day.plan("b", "09:30", "10:30"), Day.plan("c", "11:00", "12:00")], on: Day.noon, calendar: calendar)
        #expect(segments.map(\.block.id) == ["a", "b", "c"])
        #expect(segments.map(\.lane) == [0, 1, 0])
        #expect(segments.map(\.lanes) == [2, 2, 1])
        #expect(segments[0].startMin == 540)
    }

    @Test func countsWallClockMinutesOnTheFallBackSunday() throws {
        let sunday = Day.at("12:00", "2026-11-01")
        let plan = Plan(id: "p", title: "p", body: nil, rsvp: nil, startAt: try Date("2026-11-01T07:30:00-05:00", strategy: .iso8601), endAt: try Date("2026-11-01T08:30:00-05:00", strategy: .iso8601), allDay: false, timeZone: nil, attended: nil, place: nil, hub: nil, owner: "manual", notes: [])
        let segment = try #require(PlannerLayout.segments([plan], on: sunday, calendar: calendar).first)
        #expect(segment.startMin == 450)
        #expect(segment.endMin == 510)
    }

    @Test func aShortPlanIsDrawnForItsMinimumHeight() {
        let segments = PlannerLayout.segments([Day.plan("a", "09:00", "09:20"), Day.plan("b", "09:25", "10:00")], on: Day.noon, calendar: calendar)
        #expect(segments[0].drawnEndMin == 540 + PlannerLayout.minimumSpan)
        #expect(segments.map(\.lane) == [0, 1])
    }

    @Test func freeTimeIsNamedFromThirtyMinutesAndDeclinedPlansDoNotInterruptIt() {
        let segments = PlannerLayout.segments([Day.plan("a", "09:00", "10:00"), Day.plan("b", "10:20", "10:40"), Day.plan("c", "11:00", "12:00")], on: Day.noon, calendar: calendar)
        #expect(PlannerLayout.gaps(segments).isEmpty)
        let declined = PlannerLayout.segments([Day.plan("a", "09:00", "10:00"), Day.plan("b", "10:20", "11:20", rsvp: .no), Day.plan("c", "11:00", "12:00")], on: Day.noon, calendar: calendar)
        #expect(PlannerLayout.gaps(declined) == [PlannerLayout.Gap(startMin: 600, endMin: 660)])
    }

    @Test func theDayOpens45MinutesBeforeNowOrTheNextPlan() {
        let segments = PlannerLayout.segments([Day.plan("a", "09:30", "10:30"), Day.plan("b", "13:00", "14:20")], on: Day.noon, calendar: calendar)
        #expect(PlannerLayout.opening(segments, nowMinute: 11 * 60) == 9 * 60 + 30)
        #expect(PlannerLayout.opening(segments, nowMinute: 9 * 60 + 40) == 8 * 60 + 0)
        #expect(PlannerLayout.opening(segments, nowMinute: 22 * 60) == 8 * 60)
        #expect(PlannerLayout.opening(segments, nowMinute: nil) == 8 * 60)
        #expect(PlannerLayout.opening([], nowMinute: 15 * 60) == 14 * 60)
        #expect(PlannerLayout.opening([], nowMinute: nil) == 7 * 60)
    }

    @Test func theWeekOpensOneHourBeforeTheEarliestPlan() {
        let columns = [PlannerLayout.segments([Day.plan("a", "09:30", "10:30")], on: Day.noon, calendar: calendar), []]
        #expect(PlannerLayout.weekOpening(columns) == 8 * 60)
        #expect(PlannerLayout.weekOpening([[]]) == 7 * 60)
    }

    @Test func aPlanInAnotherZoneShowsItsOwnClockOnlyWhenTheOffsetDiffers() throws {
        let detroit = try #require(TimeZone(identifier: "America/Detroit"))
        let local = Plan(id: "p", title: "p", body: nil, rsvp: nil, startAt: Day.at("09:00"), endAt: Day.at("10:00"), allDay: false, timeZone: "America/New_York", attended: nil, place: nil, hub: nil, owner: "manual", notes: [])
        #expect(PlanZone.plannedClock(local, device: detroit) == nil)
        let abroad = Plan(id: "p", title: "p", body: nil, rsvp: nil, startAt: Day.at("09:00"), endAt: Day.at("10:00"), allDay: false, timeZone: "America/Los_Angeles", attended: nil, place: nil, hub: nil, owner: "manual", notes: [])
        let words = try #require(PlanZone.plannedClock(abroad, device: detroit))
        #expect(words.hasPrefix("In Los Angeles: ") && words.hasSuffix("PST"))
    }
}

/// Which plans each view draws, from the one filter.
struct PlanFilterTests {
    private let calendar = Day.calendar
    private let trip = Plan(id: "trip", title: "Career fair", body: nil, rsvp: nil, startAt: Day.at("00:00", "2026-11-21"), endAt: Day.at("23:59", "2026-11-22"), allDay: true, timeZone: nil, attended: nil, place: nil, hub: nil, owner: "manual", notes: [])

    @Test func theGridTakesTimedPlansWithAnEndAndTheBandTakesTheRest() {
        let timed = Day.plan("a", "09:00", "10:00")
        let overnight = Plan(id: "n", title: "n", body: nil, rsvp: nil, startAt: Day.at("22:00"), endAt: Day.at("02:00", "2026-11-16"), allDay: false, timeZone: nil, attended: nil, place: nil, hub: nil, owner: "manual", notes: [])
        let loose = Day.plan("l", "09:00", nil)
        let all = [timed, overnight, trip, loose]
        #expect(PlanFilter.grid(all).map(\.id) == ["a", "n"])
        #expect(PlanFilter.band(all, calendar: calendar).map(\.id) == ["n", "trip"])
        #expect(PlanFilter.loose(all).map(\.id) == ["l"])
    }

    @Test func aMonthTileListsAllDayPlansFirstAndCountsTheRest() {
        let plans = [Day.plan("a", "09:00", "10:00"), Day.plan("b", "10:00", "11:00"), Day.plan("c", "11:00", "12:00"), Plan(id: "w", title: "w", body: nil, rsvp: nil, startAt: Day.at("00:00"), endAt: Day.at("23:59"), allDay: true, timeZone: nil, attended: nil, place: nil, hub: nil, owner: "manual", notes: [])]
        let tile = PlanFilter.monthTile(plans, day: Day.noon, limit: 2, calendar: calendar)
        #expect(tile.shown.map(\.id) == ["w", "a"] && tile.more == 2)
    }

    @Test func aMultiDayBarShowsItsSpanAndOpenEnds() {
        #expect(PlanFilter.spanRange(trip, calendar: calendar) == "Nov 21 – 22")
        #expect(PlanFilter.spanRange(Day.plan("a", "09:00", "10:00"), calendar: calendar) == nil)
        let first = PlanFilter.barEdges(trip, day: Day.at("12:00", "2026-11-21"), calendar: calendar)
        #expect(!first.before && first.after)
        let second = PlanFilter.barEdges(trip, day: Day.at("12:00", "2026-11-22"), calendar: calendar)
        #expect(second.before && !second.after)
    }

    @Test func weekMarksJoinTheDaysAMultiDayPlanCovers() {
        let days = (20...24).map { Day.at("12:00", "2026-11-\($0)") }
        let marks = PlanFilter.allDayMarks([trip, Day.plan("a", "09:00", "10:00", date: "2026-11-23")], days: days, calendar: calendar)
        #expect(marks[0] == nil && marks[3] == nil && marks[4] == nil)
        #expect(marks[1] == AllDayMark(titles: ["Career fair"], fromPrev: false, toNext: true))
        #expect(marks[2] == AllDayMark(titles: ["Career fair"], fromPrev: true, toNext: false))
    }

    @Test func oneAgentKeepsAPlanOnlyWhileItIsActive() {
        #expect(PlanOwner.agent("health-specialist", active: { _ in true }) == "health-specialist")
        #expect(PlanOwner.agent("health-specialist", active: { _ in false }) == nil)
        #expect(PlanOwner.agent("manual", active: { _ in true }) == nil)
        #expect(PlanOwner.agent("ingest", active: { _ in true }) == nil)
        #expect(PlanOwner.keptBy("ingest") == nil && PlanOwner.keptBy("cse-300-specialist") == "cse-300-specialist")
    }

    @Test func theMonthGridRunsWholeWeeksFromMonday() {
        let grid = PlannerLayout.monthGrid(Day.noon, calendar: calendar)
        #expect(grid.count % 7 == 0)
        #expect(calendar.component(.weekday, from: grid[0]) == 2)
    }
}

/// A formatted clock with its narrow no-break spaces read as plain ones, so a test compares words.
private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202f}", with: " ").replacingOccurrences(of: "\u{a0}", with: " ")
}

/// The words the Planner uses: durations exact under three hours, whole hours after, then days.
struct PhraseTests {
    private let calendar = Day.calendar

    @Test func durationsAreExactUnderThreeHours() {
        #expect(Phrase.duration(25 * 60) == "25 min")
        #expect(Phrase.duration(90 * 60) == "1 h 30 min")
        #expect(Phrase.duration(20) == "under a minute" && Phrase.duration(30 * 60) == "30 min")
        #expect(Phrase.duration(3 * 24 * 3600) == "3 days")
    }

    @Test func relativePhrasesRoundToWholeHoursFromThreeHoursThenDays() {
        #expect(Phrase.coarse(179 * 60) == "2 h 59 min")
        #expect(Phrase.coarse(8 * 3600 + 7 * 60) == "8 h")
        #expect(Phrase.inPhrase(17 * 60) == "in 17 min")
        #expect(Phrase.inPhrase(10) == "now")
        #expect(Phrase.agoPhrase(2 * 24 * 3600) == "2 days ago")
        #expect(Phrase.agoPhrase(5) == "just now")
    }

    @Test func daysAreNamedRelativeToNow() {
        let now = Day.noon
        #expect(Phrase.dayWord(Day.at("09:00", "2026-11-16"), now: now, calendar: calendar) == "tomorrow")
        #expect(Phrase.dayWord(Day.at("09:00", "2026-11-14"), now: now, calendar: calendar) == "yesterday")
        #expect(Phrase.dayWord(Day.at("09:00", "2026-11-20"), now: now, calendar: calendar) == "Fri")
        #expect(Phrase.dayWord(Day.at("09:00", "2026-11-28"), now: now, calendar: calendar) == "Nov 28")
        #expect(plain(Phrase.moment(Day.at("23:59", "2026-11-20"), now: now, calendar: calendar)) == "Fri 11:59 PM")
    }

    @Test func lastConfirmedNamesHowLongAgo() {
        #expect(Phrase.confirmed(Day.at("12:00", "2026-11-12"), now: Day.noon) == "Last confirmed 3 days ago")
        #expect(Phrase.confirmed(nil, now: Day.noon) == nil)
    }
}

/// Where a plan or task stands in time, and what it says about itself.
struct TimeStateTests {
    private let calendar = Day.calendar

    @Test func aPlanIsPastNowNextOrLater() {
        let plans = [Day.plan("past", "09:00", "10:00"), Day.plan("now", "11:30", "12:30"), Day.plan("next", "14:00", "15:00"), Day.plan("later", "16:00", "17:00")]
        let nextID = PlanTime.nextPlanID(plans, now: Day.noon, calendar: calendar)
        #expect(nextID == "next")
        #expect(plans.map { PlanTime.state($0, now: Day.noon, nextID: nextID) } == [.past, .now, .next, .later])
    }

    @Test func aDeclinedPlanIsNeverNowOrNext() {
        let declined = Day.plan("d", "11:30", "12:30", rsvp: .no)
        #expect(PlanTime.state(declined, now: Day.noon, nextID: nil) == .later)
        #expect(PlanTime.nextPlanID([Day.plan("d", "14:00", "15:00", rsvp: .no)], now: Day.noon, calendar: calendar) == nil)
        #expect(PlanTime.state(Day.plan("d", "09:00", "10:00", rsvp: .no), now: Day.noon, nextID: nil) == .past)
    }

    @Test func statusReadsAsALabelledPhrase() {
        func status(_ plan: Plan) -> String {
            plain(PlanTime.status(plan, now: Day.noon, state: PlanTime.state(plan, now: Day.noon, nextID: PlanTime.nextPlanID([plan], now: Day.noon, calendar: calendar)), calendar: calendar))
        }
        #expect(status(Day.plan("a", "11:30", "12:42")) == "Now · 42 min left")
        #expect(status(Day.plan("b", "12:25", "13:00")) == "Starts in 25 min")
        #expect(status(Day.plan("c", "09:00", "10:00")) == "Ended 2 h ago")
        #expect(status(Day.plan("d", "09:00", "10:00", date: "2026-11-14")) == "Ended yesterday")
        #expect(status(Day.plan("e", "09:00", "10:00", date: "2026-11-16")) == "Starts tomorrow 9:00 AM")
        #expect(status(Day.plan("f", "00:00", "23:59", allDay: true)) == "All day")
    }

    @Test func aPlanThatEndedAddsWhatAnkurSaid() {
        let plan = Day.plan("a", "03:00", "04:00", attended: true)
        #expect(PlanTime.situation(plan, now: Day.noon, state: .past, calendar: calendar) == "Ended 8 h ago · Attended")
    }

    @Test func aWeekSummaryNamesTheBusiestDay() {
        let days = (15...21).map { Day.at("12:00", "2026-11-\($0)") }
        let plans = [Day.plan("a", "09:00", "10:00"), Day.plan("b", "11:00", "12:00", date: "2026-11-17"), Day.plan("c", "13:00", "14:00", date: "2026-11-17")]
        #expect(PlanTime.periodSummary(plans, days: days, noun: "week", calendar: calendar) == "3 plans this week · busiest Tuesday with 2")
        #expect(PlanTime.periodSummary([], days: days, noun: "week", calendar: calendar) == "Nothing planned this week")
    }

    @Test func aTaskSaysWhereItStands() {
        func status(_ task: PlanTask) -> TaskStatus {
            let found = PlanTime.taskStatus(task, now: Day.noon, calendar: calendar)
            return TaskStatus(label: plain(found.label), tone: found.tone)
        }
        #expect(status(Day.task("a", closes: Day.at("12:17"))) == TaskStatus(label: "Closes today 12:17 PM · in 17 min", tone: .soon))
        #expect(status(Day.task("b", closes: Day.at("23:59", "2026-11-20"))) == TaskStatus(label: "Closes Fri 11:59 PM · in 5 days", tone: .open))
        #expect(status(Day.task("c", closes: Day.at("23:59", "2026-11-10"))) == TaskStatus(label: "Past due by 5 days", tone: .late))
        #expect(status(Day.task("d")) == TaskStatus(label: "No close date", tone: .none))
        #expect(status(Day.task("e", done: true)) == TaskStatus(label: "Done", tone: .done))
    }
}

/// A day's checklist: its groups, sorting, one meta line, course label and Someday groups.
struct TaskLogicTests {
    private let calendar = Day.calendar

    @Test func tasksGroupIntoPastDueOpenAndDone() {
        let tasks = [
            Day.task("late", closes: Day.at("23:59", "2026-11-13"), pastDue: true),
            Day.task("soon", closes: Day.at("17:00")),
            Day.task("later", closes: Day.at("23:59", "2026-11-17")),
            Day.task("done", closes: Day.at("09:00"), done: true),
            Day.task("future", opens: "2026-11-20", closes: Day.at("23:59", "2026-11-22")),
            Day.task("someday", opens: nil),
        ]
        let groups = TaskLogic.groups(tasks, on: Day.noon, calendar: calendar)
        #expect(groups.pastDue.map(\.id) == ["late"])
        #expect(groups.open.map(\.id) == ["soon", "later"])
        #expect(groups.done.map(\.id) == ["done"])
        #expect(TaskLogic.progress(groups) == (1, 4))
    }

    @Test func theMetaLineCombinesStatusAndCourseUnlessTheTitleNamesIt() {
        let hub = Hub(id: "h", title: "IBIO 150 class")
        func task(_ title: String, hub: Hub?) -> PlanTask {
            PlanTask(id: "t", title: title, body: nil, opensOn: "2026-11-01", closesAt: Day.at("23:59", "2026-11-03"), done: false, verifiedAt: nil, createdAt: Day.noon, updatedAt: Day.noon, pastDue: true, hub: hub, owner: "manual")
        }
        #expect(TaskLogic.meta(task("Codon survey due", hub: hub), now: Day.noon, calendar: calendar) == "Past due by 12 days · IBIO 150 class")
        #expect(TaskLogic.meta(task("IBIO 150 — Codon survey", hub: hub), now: Day.noon, calendar: calendar) == "Past due by 12 days")
        #expect(TaskLogic.meta(task("Read IBIO 150 class notes", hub: hub), now: Day.noon, calendar: calendar) == "Past due by 12 days")
        #expect(TaskLogic.meta(task("Pay rent", hub: nil), now: Day.noon, calendar: calendar) == "Past due by 12 days")
    }

    @Test func repeatedTitlesGroupUnderOneLabelWithoutTheirNumber() {
        let groups = TaskLogic.groupByTitle([Day.task("a", title: "Gym training split 1"), Day.task("b", title: "Gym training split 12"), Day.task("c", title: "Organize the garage")])
        #expect(groups.map(\.label) == ["Gym training split", "Organize the garage"])
        #expect(groups[0].items.count == 2 && groups[1].items.count == 1)
    }

    @Test func aSomedayTaskShowsCheckedAgoOnlyFromADayOn() {
        #expect(TaskLogic.checkedAgo(Day.task("a", verified: Day.at("12:00", "2026-11-12")), now: Day.noon) == "checked 3d ago")
        #expect(TaskLogic.checkedAgo(Day.task("a", verified: Day.at("06:00")), now: Day.noon) == nil)
        #expect(TaskLogic.checkedAgo(Day.task("a"), now: Day.noon) == nil)
    }

    @Test func aWeekBadgeCountsOpenTasksAndTintsUrgentOnes() {
        let badge = TaskLogic.dayBadge([Day.task("a", closes: Day.at("23:59")), Day.task("b", closes: Day.at("23:59", "2026-11-20"))], on: Day.noon, now: Day.noon, calendar: calendar)
        #expect(badge == DayBadge(open: 2, urgent: true, allDone: false))
        #expect(TaskLogic.dayBadge([Day.task("a", closes: Day.at("17:00"), done: true)], on: Day.noon, now: Day.noon, calendar: calendar).allDone)
    }
}

/// The widget fits the day or follows it, and recaps it once it is over.
struct WidgetLogicTests {
    private func hourly(_ count: Int) -> [Plan] {
        (0..<count).map { Day.plan("p\($0)", String(format: "%02d:00", 8 + $0), String(format: "%02d:40", 8 + $0)) }
    }

    @Test func aDayThatFitsShowsEveryRowWithFreeTimeBetween() {
        let window = WidgetLogic.window(hourly(3), now: Day.noon, capacity: 600)
        #expect(window.rows.count == 5 && window.earlier == 0 && window.later == 0)
        if case .free(let minutes) = window.rows[1] { #expect(minutes == 20) } else { Issue.record("expected free time") }
    }

    @Test func aLongDayFollowsTheCurrentPlanWithEarlierAndLater() {
        let window = WidgetLogic.window(hourly(10), now: Day.at("12:10"), capacity: 250)
        let current = window.rows.compactMap { row -> String? in if case .plan(let plan, true) = row { plan.id } else { nil } }
        #expect(current == ["p4"])
        #expect(window.earlier > 0 && window.later > 0)
    }

    @Test func afterTheLastPlanTheWindowEndsOnTheLastOne() {
        let window = WidgetLogic.window(hourly(10), now: Day.at("23:00"), capacity: 150)
        #expect(window.later == 0 && window.earlier > 0)
    }

    @Test func theTileHoldsTimedPlansWithAnEndOnTheDay() {
        let plans = [Day.plan("a", "10:00", "11:00"), Day.plan("b", "10:00", nil), Day.plan("c", "00:00", "23:59", allDay: true), Day.plan("d", "10:00", "11:00", date: "2026-11-16")]
        #expect(WidgetLogic.tilePlans(plans, on: Day.noon, calendar: Day.calendar).map(\.id) == ["a"])
    }

    @Test func theDayIsOverWhenEveryKeptPlanHasEndedAndTheRecapCountsThem() {
        let plans = [Day.plan("a", "09:00", "10:00", attended: true), Day.plan("b", "10:00", "11:00", attended: true), Day.plan("c", "11:00", "12:00", rsvp: .no)]
        #expect(WidgetLogic.dayOver(plans, now: Day.at("13:00")))
        #expect(!WidgetLogic.dayOver(plans, now: Day.at("10:30")))
        #expect(!WidgetLogic.dayOver([], now: Day.at("13:00")))
        #expect(WidgetLogic.recap(plans, tasks: (0, 8)) == "2 plans done · 2 attended · 0 of 8 tasks")
    }
}

/// A tick shows at once, is put back with its reason when it is not saved, and offers Undo.
@MainActor
struct TaskTickerTests {
    private enum Refused: LocalizedError {
        case offline
        var errorDescription: String? { "dadi is offline" }
    }

    @Test func aTickShowsAtOnceAndSavesWhatWasAsked() async {
        let saved = Saved()
        let ticker = TaskTicker { id, done in await saved.add("\(id):\(done)") }
        let task = Day.task("t1")
        let write = ticker.tick(id: task.id, title: task.title, done: true)
        #expect(ticker.isDone(task))
        #expect(ticker.shown([task])[0].done)
        #expect(ticker.undo?.id == "t1")
        await write.value
        #expect(await saved.items == ["t1:true"])
        #expect(ticker.marks["t1"]?.confirmed == true && ticker.failure == nil)
    }

    @Test func aTickThatFailsIsPutBackWithTheReason() async {
        let ticker = TaskTicker { _, _ in throw Refused.offline }
        let task = Day.task("t1")
        await ticker.tick(id: task.id, title: task.title, done: true).value
        #expect(!ticker.isDone(task))
        #expect(ticker.marks["t1"] == nil && ticker.undo == nil)
        #expect(ticker.failure?.message == "dadi is offline" && ticker.failure?.title == "t1")
    }

    @Test func aRowStaysInItsGroupUntilItHasLeft() async throws {
        let ticker = TaskTicker { _, _ in }
        let task = Day.task("t1", closes: Day.at("17:00"))
        await ticker.tick(id: task.id, title: task.title, done: true).value
        #expect(ticker.placed([task])[0].done == false)
        #expect(ticker.shown([task])[0].done)
        try await Task.sleep(for: .milliseconds(700))
        #expect(ticker.placed([task])[0].done)
        ticker.settle()
        #expect(ticker.marks.isEmpty)
    }

    @Test func undoTakesTheTickBack() async {
        let saved = Saved()
        let ticker = TaskTicker { id, done in await saved.add("\(id):\(done)") }
        await ticker.tick(id: "t1", title: "Pay rent", done: true).value
        ticker.undoLast()
        #expect(!ticker.isDone(Day.task("t1", done: true)))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await saved.items == ["t1:true", "t1:false"])
    }

    @Test func aTickYaadHasNotSavedSurvivesAReload() async {
        let ticker = TaskTicker { _, _ in try await Task.sleep(for: .seconds(5)) }
        ticker.tick(id: "t1", title: "Pay rent", done: true)
        ticker.settle()
        #expect(ticker.marks["t1"] != nil)
    }
}

private actor Saved {
    private(set) var items: [String] = []
    func add(_ item: String) { items.append(item) }
}


/// Answers every request with a status and records its method and path, so a test sees which routes the client calls.
private final class Recording: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var seen: [(method: String, path: String, body: String)] = []
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var reply = "{}"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        var body = Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 2048)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; body.append(buffer, count: n) }
            stream.close()
        }
        Self.seen.append((request.httpMethod ?? "", request.url?.path ?? "", String(decoding: request.httpBody ?? body, as: UTF8.self)))
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    static func session(status: Int = 200, reply: String = "{}") -> URLSession {
        seen = []
        self.status = status
        self.reply = reply
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Recording.self]
        return URLSession(configuration: config)
    }
}

/// Every suite that records requests runs one at a time, since they share one recorder.
@Suite(.serialized) enum Recorded {}

extension Recorded {
/// Yaad's planner routes: the paths and bodies the client sends, and what it decodes.
struct YaadRoutesTests {
    private let plan = #"{"id":"p1","title":"Study","body":null,"rsvp":"no","start_at":"2026-11-15T14:00:00.000Z","end_at":null,"all_day":false,"time_zone":null,"attended":null,"place":{"id":"x","title":"Wells","address":null,"room":"B1"},"hub":null,"owner":"manual","notes":[]}"#

    @Test func plansPostToThePlannerRouteWithNoView() async throws {
        let yaad = YaadClient(session: Recording.session(reply: #"{"items":[\#(plan)]}"#))
        let plans = try await yaad.plans(from: Day.at("00:00"), to: Day.at("23:59"))
        #expect(Recording.seen.map(\.path) == ["/planner/plans"] && Recording.seen[0].method == "POST")
        #expect(Recording.seen[0].body.contains("\"from\"") && Recording.seen[0].body.contains("\"to\"") && !Recording.seen[0].body.contains("view"))
        #expect(plans.count == 1 && plans[0].declined && plans[0].endAt == nil && plans[0].place?.room == "B1")
    }

    @Test func tasksPostADayOrSomeday() async throws {
        let yaad = YaadClient(session: Recording.session(reply: #"{"items":[]}"#))
        _ = try await yaad.tasks(on: "2026-11-15")
        _ = try await yaad.somedayTasks()
        #expect(Recording.seen.allSatisfy { $0.path == "/planner/tasks" && $0.method == "POST" })
        #expect(Recording.seen.count == 3 && Recording.seen[0].body.contains("2026-11-15"))
        #expect(Recording.seen.dropFirst().contains { $0.body.contains("\"someday\":true") })
    }

    @Test func ticksAndAttendanceUseTheNewWriteRoutes() async throws {
        let yaad = YaadClient(session: Recording.session(reply: #"{"task_id":"t","done":true,"plan_id":"p","attended":null}"#))
        _ = try await yaad.setDone(true, task: "t")
        _ = try await yaad.setAttended(nil, plan: "p")
        #expect(Recording.seen.map(\.path) == ["/planner/tasks/done", "/planner/plans/attended"])
        #expect(Recording.seen.allSatisfy { $0.method == "PUT" })
        #expect(Recording.seen[1].body.contains("\"attended\":null"))
    }

    @Test func countsDecodeTotalAndKinds() async throws {
        let yaad = YaadClient(session: Recording.session(reply: #"{"total":320,"kinds":{"person":72,"memory":124,"place":57,"plan":64,"task":3}}"#))
        let counts = try await yaad.counts()
        #expect(Recording.seen.map(\.path) == ["/counts"] && counts.total == 320 && counts.kinds.task == 3)
    }

    @Test func aRefusedWriteSurfacesTheServicesError() async {
        let yaad = YaadClient(session: Recording.session(status: 404, reply: #"{"error":{"type":"not_found","message":"No such plan"}}"#))
        await #expect(throws: ServiceError.self) { _ = try await yaad.setAttended(true, plan: "nope") }
    }
}
}

extension Recorded {
/// Attendance shows at once, is put back when it is not saved, and RSVP only opens a chat.
@MainActor struct PlannerActionsTests {
    private func actions(status: Int = 200, message: @escaping (String, String?) -> Void = { _, _ in }) -> PlannerActions {
        PlannerActions(yaad: YaadClient(session: Recording.session(status: status, reply: status == 200 ? #"{"plan_id":"a","attended":true}"# : #"{"error":{"type":"boom","message":"boom"}}"#)), message: message, reachable: { $0 == "schedule-specialist" }, nameOf: { $0 })
    }

    @Test func anAttendanceAnswerShowsAtOnceAndIsSaved() async throws {
        let actions = actions()
        let plan = Day.plan("a", "09:00", "10:00")
        actions.setAttended(true, on: plan)
        #expect(actions.shown(plan).attended == true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(Recording.seen.map(\.path) == ["/planner/plans/attended"] && actions.attendedFailure == nil)
    }

    @Test func anAttendanceAnswerThatFailsIsPutBack() async throws {
        let actions = actions(status: 500)
        let plan = Day.plan("a", "09:00", "10:00", attended: false)
        actions.setAttended(true, on: plan)
        #expect(actions.shown(plan).attended == true)
        try await Task.sleep(for: .milliseconds(400))
        #expect(actions.shown(plan).attended == false)
        #expect(actions.attendedFailure?.contains("boom") == true)
    }

    @Test func goingOpensTheKeepersChatWithTheAnswerReadyAndWritesNothing() {
        var opened: (String, String?)?
        let actions = actions { opened = ($0, $1) }
        let plan = Day.plan("a", "14:00", "15:00", title: "Study block")
        actions.tell(plan, going: false)
        #expect(opened?.0 == "schedule-specialist" && opened?.1 == "I’m not going to Study block on Sun, Nov 15")
        #expect(Recording.seen.isEmpty)
    }

    @Test func nobodyIsMessagedForASourceOrARetiredAgent() {
        var opened = false
        let actions = actions { _, _ in opened = true }
        actions.tell(Day.plan("a", "14:00", "15:00", owner: "manual"), going: true)
        actions.messageOwner("retired-specialist")
        #expect(!opened && actions.agent(for: "manual") == nil && actions.agent(for: "retired-specialist") == nil)
    }
}
}

/// The Week's measures: one table of points on a 4 pt base, the header's height, the column tiers, the opening hour and
/// the two-lane clusters.
struct WeekMetricsTests {
    private let calendar = Day.calendar

    @Test func everyGapComesFromTheSpacingTable() {
        #expect(WeekMetrics.gaps.allSatisfy { WeekMetrics.table.contains($0) })
        let measures: [CGFloat] = [WeekMetrics.axis, WeekMetrics.bubble, WeekMetrics.barRow, WeekMetrics.hour, WeekMetrics.blockMinHeight, WeekMetrics.timeLineMinHeight]
        #expect(measures.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
    }

    @Test func theHeaderGrowsWithItsBarRowsAndTheirOverflow() {
        #expect(WeekMetrics.headerHeight(rows: 0, overflow: false) == 52)
        #expect(WeekMetrics.headerHeight(rows: 1, overflow: false) == 84)
        #expect(WeekMetrics.headerHeight(rows: 2, overflow: false) == 112)
        #expect(WeekMetrics.headerHeight(rows: 3, overflow: true) == 140)
    }

    @Test func aPhoneShowsThreeWholeColumnsBesideTheAxis() {
        #expect(WeekMetrics.column(pageWidth: 393) == 100)
        let visible = 393 - 2 * WeekMetrics.cardPad - WeekMetrics.axis - WeekMetrics.gutter
        #expect(WeekMetrics.column(pageWidth: 393) * CGFloat(WeekMetrics.visibleDays) <= visible)
        #expect(WeekMetrics.tier(column: 140) == .full && WeekMetrics.tier(column: 100) == .noCount && WeekMetrics.tier(column: 80) == .letter)
    }

    @Test func theWeekPagesOneDayAtATimeAndNeverPastTheLastFullWindow() {
        let column: CGFloat = 100
        #expect(WeekMetrics.snappedOffset(0, column: column) == 0)
        #expect(WeekMetrics.snappedOffset(40, column: column) == 0)
        #expect(WeekMetrics.snappedOffset(60, column: column) == 100)
        #expect(WeekMetrics.snappedOffset(230, column: column) == 200)
        #expect(WeekMetrics.snappedOffset(9000, column: column) == CGFloat(WeekMetrics.days - WeekMetrics.visibleDays) * column)
        #expect(WeekMetrics.snappedOffset(-50, column: column) == 0)
    }

    @Test func aDayLateInTheWeekOpensOnTheLastFullWindow() {
        #expect(WeekMetrics.offset(showing: 0, column: 100) == 0)
        #expect(WeekMetrics.offset(showing: 2, column: 100) == 200)
        #expect(WeekMetrics.offset(showing: 6, column: 100) == 400)
    }

    @Test func theWeekOpensOnTheHourBeforeTheEarliestPlanOrNow() {
        #expect(WeekMetrics.opening(starts: [9 * 60 + 30, 13 * 60], nowMinute: nil) == 8 * 60)
        #expect(WeekMetrics.opening(starts: [9 * 60 + 30], nowMinute: 7 * 60 + 10) == 6 * 60)
        #expect(WeekMetrics.opening(starts: [9 * 60 + 30], nowMinute: 15 * 60) == 8 * 60)
        #expect(WeekMetrics.opening(starts: [30], nowMinute: nil) == 0)
        #expect(WeekMetrics.opening(starts: [], nowMinute: nil) == 6 * 60)
    }

    @Test func overlapsShowTwoLanesAndFoldTheRestIntoPlusN() {
        let plans = [Day.plan("a", "09:00", "10:00"), Day.plan("b", "09:15", "10:15"), Day.plan("c", "09:30", "10:30"), Day.plan("d", "09:45", "10:45"), Day.plan("e", "13:00", "14:00")]
        let clusters = WeekLayout.clusters(PlannerLayout.segments(plans, on: Day.noon, minimum: 26, calendar: calendar))
        #expect(clusters.count == 2)
        #expect(clusters[0].placed.map(\.segment.block.id) == ["a", "b"] && clusters[0].placed.allSatisfy { $0.lanes == 2 })
        #expect(clusters[0].folded.map(\.id) == ["c", "d"])
        #expect(clusters[1].placed.map(\.lanes) == [1] && clusters[1].folded.isEmpty)
    }
}

extension Recorded {
/// A task with no close is Someday wherever tasks are counted, even when it has an opening.
struct SomedayTaskTests {
    private let calendar = Day.calendar

    @Test func aTaskWithOnlyAnOpeningIsSomedayAndLeavesTheChecklistAndBadges() {
        let opening = Day.task("open-only", opens: "2026-11-10", closes: nil)
        let dated = Day.task("dated", closes: Day.at("17:00"))
        #expect(TaskLogic.isSomeday(opening) && !TaskLogic.isSomeday(dated))
        let groups = TaskLogic.groups([opening, dated], on: Day.noon, calendar: calendar)
        #expect(groups.open.map(\.id) == ["dated"] && TaskLogic.progress(groups) == (0, 1))
        #expect(TaskLogic.dayBadge([opening, dated], on: Day.noon, now: Day.noon, calendar: calendar).open == 1)
        #expect(!TaskLogic.dayBadge([Day.task("d", closes: nil, done: true)], on: Day.noon, now: Day.noon, calendar: calendar).allDone)
    }

    @Test func theSomedayListHoldsEachOpenSomedayTaskOnce() {
        let a = Day.task("a", title: "Banana", opens: nil)
        let b = Day.task("b", title: "Apple", opens: "2026-11-10")
        let done = Day.task("c", opens: nil, done: true)
        let dated = Day.task("d", closes: Day.at("17:00"))
        #expect(TaskLogic.someday([a, b, a, done, dated]).map(\.id) == ["b", "a"])
    }

    @Test func theSomedayRequestJoinsTheWindowlessListWithTodaysUndatedTasks() async throws {
        let json = #"{"items":[{"id":"w","title":"W","body":null,"opens_on":null,"closes_at":null,"done":false,"verified_at":null,"created_at":"2026-11-01T08:00:00.000Z","updated_at":"2026-11-01T08:00:00.000Z","past_due":false,"hub":null,"owner":"manual"}]}"#
        let yaad = YaadClient(session: Recording.session(reply: json))
        let tasks = try await yaad.somedayTasks()
        #expect(tasks.map(\.id) == ["w"])
        #expect(Recording.seen.count == 2 && Recording.seen.allSatisfy { $0.path == "/planner/tasks" })
    }
}
}

/// Video-call links: found in a plan's place, body or notes, named by service, and never taken for an address.
struct MeetingLinkTests {
    private func plan(address: String? = nil, title: String = "Call", body: String? = nil, notes: [PlanNote] = []) -> Plan {
        Plan(id: "p", title: "Advising", body: body, rsvp: nil, startAt: Day.at("10:00"), endAt: Day.at("11:00"), allDay: false, timeZone: nil, attended: nil, place: PlanPlace(id: "x", title: title, address: address, room: nil), hub: nil, owner: "manual", notes: notes)
    }

    @Test func namesTheServiceAndHost() {
        let zoom = meetingLink(plan(address: "https://us02web.zoom.us/j/123?pwd=a"))
        #expect(zoom?.service == "Zoom" && zoom?.host == "us02web.zoom.us")
        #expect(meetingLink(plan(body: "Join at https://meet.google.com/abc-defg-hij please"))?.service == "Google Meet")
        #expect(meetingLink(plan(notes: [PlanNote(id: "n", title: "Link", body: "https://teams.microsoft.com/l/meetup-join/x")]))?.service == "Microsoft Teams")
        #expect(meetingLink(plan(title: "https://acme.webex.com/meet/jo"))?.service == "Video call")
        #expect(meetingLink(plan(body: "https://facetime.apple.com/join#v=1"))?.service == "Video call")
    }

    @Test func aPlanWithoutACallLinkHasNone() {
        #expect(meetingLink(plan(address: "619 Red Cedar Rd, East Lansing", body: "See https://example.com/syllabus")) == nil)
        #expect(meetingLink(plan(title: "Wells Hall")) == nil)
    }

    @Test func aLinkIsNeverAStreetAddress() {
        #expect(plan(address: "https://zoom.us/j/1").street == nil)
        #expect(plan(address: "619 Red Cedar Rd").street == "619 Red Cedar Rd")
        #expect(Directions.url(to: plan(address: "https://zoom.us/j/1").place) == nil)
        #expect(Directions.url(to: plan(address: "619 Red Cedar Rd").place) != nil)
    }
}

/// The Planner's route: one thing at a time, set from the drawer, Week and Month, and a re-tap of the tab.
struct PlannerRouteTests {
    private let calendar = Day.calendar

    @Test func theDrawerSwitchesBetweenTimelineAndChecklist() {
        var route = PlannerRoute()
        route.show(.week)
        let checklist = PlannerDrawer.picking(.checklist, from: route)
        #expect(checklist.section == .checklist && checklist.mode == .week)
        let back = PlannerDrawer.picking(.timeline, from: checklist)
        #expect(back.section == .timeline && back.mode == .week)
        let month = PlannerDrawer.picking(.month, from: checklist)
        #expect(month.section == .timeline && month.mode == .month && month.day == nil)
    }

    @Test func aDayOpenedFromWeekIsNotTheRootUnlessItIsToday() {
        var route = PlannerRoute()
        route.open(day: Day.at("12:00", "2026-11-17"), calendar: calendar)
        #expect(route.mode == .day && !route.isRoot(calendar: calendar, now: Day.noon))
        route.open(day: Day.noon, calendar: calendar)
        #expect(route.isRoot(calendar: calendar, now: Day.noon))
    }

    @Test func reselectingResetsASubStateToTimelineTodayAndScrollsOnlyAtTheRoot() {
        var route = PlannerRoute(section: .checklist, mode: .month, day: nil)
        #expect(route.reselect(calendar: calendar, now: Day.noon) == false)
        #expect(route == PlannerRoute() && route.isRoot(calendar: calendar, now: Day.noon))
        #expect(route.reselect(calendar: calendar, now: Day.noon) == true)
        route.open(day: Day.at("12:00", "2026-11-18"), calendar: calendar)
        #expect(route.reselect(calendar: calendar, now: Day.noon) == false && route.day == nil)
    }
}


/// How a plan card looks, so Attended reads at a glance: solid and sage with a firm border, never just a small check.
struct PlanCardLookTests {
    @Test func theCardStateFollowsWhatAnkurSaidThenTheClock() {
        let plan = Day.plan("p", "09:00", "10:00")
        #expect(PlanCardState.of(plan, state: .past) == .past)
        #expect(PlanCardState.of(plan, state: .now) == .current)
        #expect(PlanCardState.of(plan, state: .next) == .upcoming && PlanCardState.of(plan, state: .later) == .upcoming)
        #expect(PlanCardState.of(Day.plan("p", "09:00", "10:00", attended: true), state: .past) == .attended)
        #expect(PlanCardState.of(Day.plan("p", "09:00", "10:00", attended: true), state: .now) == .attended)
        #expect(PlanCardState.of(Day.plan("p", "09:00", "10:00", attended: false), state: .past) == .missed)
        #expect(PlanCardState.of(Day.plan("p", "09:00", "10:00", rsvp: .no, attended: true), state: .past) == .declined)
    }

    @Test func anAttendedCardIsSolidFirmlyBorderedAndCaptioned() {
        let attended = PlanCardLook(.attended)
        #expect(attended.fill == .attended && attended.border == .attended && attended.lineWidth > PlanCardLook(.upcoming).lineWidth)
        #expect(attended.check && attended.caption == "Attended" && attended.opacity == 1 && !attended.dashed)
    }

    @Test func aPastUnansweredCardIsQuietAndADidntAttendCardIsMutedDashedAndStruck() {
        let past = PlanCardLook(.past)
        #expect(past.opacity < 1 && !past.dashed && !past.struck && past.caption == nil && !past.check)
        let missed = PlanCardLook(.missed)
        #expect(missed.dashed && missed.struck && missed.opacity < 1 && missed.fill == .none && missed.caption == "Didn’t attend")
        let declined = PlanCardLook(.declined)
        #expect(declined.dashed && !declined.struck)
    }

    @Test func everyStateLooksDifferent() {
        let looks = [PlanCardState.upcoming, .current, .past, .attended, .missed, .declined].map { PlanCardLook($0) }
        #expect(Set(looks.map { "\($0.fill)|\($0.border)|\($0.dashed)|\($0.opacity)|\($0.struck)" }).count == looks.count)
    }
}

/// The month pager: months to page through, each a whole-week grid with the neighbours' head and tail days dimmed.
@MainActor struct MonthPagingTests {
    private let calendar = Day.calendar
    private let november = Day.midnight("2026-11-01")

    @Test func thePagerReachesMonthsEitherSideOfTheCurrentOne() {
        let months = MonthPaging.months(around: Day.noon, calendar: calendar)
        #expect(months.count == 2 * MonthPaging.reach + 1)
        #expect(months[MonthPaging.reach] == november)
        #expect(months.allSatisfy { calendar.component(.day, from: $0) == 1 })
    }

    @Test func aMonthPageHoldsWholeWeeksWithHeadAndTailDays() {
        let days = PlannerLayout.monthGrid(november, calendar: calendar)
        #expect(days.count == 42 && days.count % 7 == 0)
        #expect(calendar.component(.weekday, from: days[0]) == 2)
        #expect(calendar.component(.month, from: days[0]) == 10 && calendar.component(.day, from: days[0]) == 26)
        #expect(calendar.component(.month, from: days[41]) == 12 && calendar.component(.day, from: days[41]) == 6)
    }

    @Test func onlyTheFocusedMonthsDaysAreAtFullStrength() {
        let days = PlannerLayout.monthGrid(november, calendar: calendar)
        let focused = days.filter { MonthPaging.isFocused($0, in: november, calendar: calendar) }
        #expect(focused.count == 30)
        #expect(days.count - focused.count == 12)
        #expect(!MonthPaging.isFocused(days[0], in: november, calendar: calendar) && !MonthPaging.isFocused(days[41], in: november, calendar: calendar))
    }

    @Test func oneReadCoversTheMonthAndBothNeighboursWholeWeeks() throws {
        let window = try #require(MonthPaging.window(of: november, calendar: calendar))
        #expect(calendar.component(.month, from: window.from) == 9 && calendar.component(.day, from: window.from) == 28)
        #expect(calendar.component(.month, from: window.to) == 1 && calendar.component(.day, from: window.to) == 4)
    }
}

/// The drawer is the Planner's control centre: its choices change the one route, its month marks the days with plans.
@MainActor struct PlannerDrawerLogicTests {
    private let calendar = Day.calendar

    @Test func pickingADayOnTheMonthOpensItInTheDayViewFromAnyPage() {
        var route = PlannerRoute()
        route.showChecklist()
        let picked = PlannerDrawer.picking(day: Day.at("15:00", "2026-11-20"), from: route, calendar: calendar)
        #expect(picked.section == .timeline && picked.mode == .day)
        #expect(picked.day == Day.at("00:00", "2026-11-20"))
    }

    @Test func aDimmedDayOfAnotherMonthOpensToo() {
        let picked = PlannerDrawer.picking(day: Day.midnight("2026-10-28"), from: PlannerRoute(), calendar: calendar)
        #expect(picked.day == Day.midnight("2026-10-28") && picked.mode == .day)
    }

    @Test func theMonthChoosesTheDayOnlyWhileTheDayViewShowsOne() {
        var route = PlannerRoute()
        #expect(PlannerDrawer.selectedDay(route, now: Day.noon, calendar: calendar) == Day.at("00:00"))
        route.open(day: Day.at("12:00", "2026-11-18"), calendar: calendar)
        #expect(PlannerDrawer.selectedDay(route, now: Day.noon, calendar: calendar) == Day.at("00:00", "2026-11-18"))
        route.show(.week)
        #expect(PlannerDrawer.selectedDay(route, now: Day.noon, calendar: calendar) == nil)
        route.showChecklist()
        #expect(PlannerDrawer.selectedDay(route, now: Day.noon, calendar: calendar) == nil)
    }

    @Test func theViewPickKeepsTimelineAndTheSectionPickKeepsTheView() {
        var route = PlannerRoute()
        route.show(.month)
        let checklist = PlannerDrawer.picking(.checklist, from: route)
        #expect(checklist.section == .checklist && checklist.mode == .month)
        let week = PlannerDrawer.picking(.week, from: checklist)
        #expect(week.section == .timeline && week.mode == .week)
    }

    @Test func aDayIsMarkedWhenItHoldsAPlanAnkurKeeps() {
        let days = [Day.at("00:00"), Day.at("00:00", "2026-11-16"), Day.at("00:00", "2026-11-17"), Day.at("00:00", "2026-11-18")]
        let plans = [
            Day.plan("a", "09:00", "10:00"),
            Day.plan("b", "09:00", "10:00", rsvp: .no, date: "2026-11-16"),
            Day.plan("c", "09:00", "10:00", date: "2026-11-17"),
        ]
        let marks = MiniCalendar.marks(plans, days: days, calendar: calendar)
        #expect(marks == [Day.at("00:00"), Day.at("00:00", "2026-11-17")])
    }

    @Test func nowAndNextAreTheKeptPlansOnAndComingToday() {
        let plans = [Day.plan("past", "09:00", "10:00"), Day.plan("now", "11:30", "12:30"), Day.plan("skipped", "13:00", "14:00", rsvp: .no), Day.plan("next", "14:00", "15:00"), Day.plan("later", "16:00", "17:00")]
        let glance = PlannerDrawer.nowNext(plans, now: Day.noon, calendar: calendar)
        #expect(glance.current?.id == "now" && glance.next?.id == "next")
        let over = PlannerDrawer.nowNext(plans, now: Day.at("18:00"), calendar: calendar)
        #expect(over.current == nil && over.next == nil)
    }

    @Test func aDayCardSaysHowFarTheDayIs() {
        let now = Day.noon
        #expect(DayCardSheet.relation(Day.at("00:00"), now: now, calendar: calendar) == "Today")
        #expect(DayCardSheet.relation(Day.at("00:00", "2026-11-16"), now: now, calendar: calendar) == "Tomorrow")
        #expect(DayCardSheet.relation(Day.at("00:00", "2026-11-14"), now: now, calendar: calendar) == "Yesterday")
        #expect(DayCardSheet.relation(Day.at("00:00", "2026-11-21"), now: now, calendar: calendar) == "In 6 days")
        #expect(DayCardSheet.relation(Day.at("00:00", "2026-11-03"), now: now, calendar: calendar) == "12 days ago")
    }
}
