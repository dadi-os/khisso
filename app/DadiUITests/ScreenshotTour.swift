import XCTest

/// Read-only tour of the installed app against live data: navigates and opens drawers only, then attaches a screenshot per screen.
@MainActor
final class ScreenshotTour: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func need(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 15) {
        guard element.waitForExistence(timeout: timeout) else {
            shot("FAILED-\(what)")
            XCTFail("missing: \(what)")
            return
        }
    }

    private func settle(_ seconds: TimeInterval = 1.5) { Thread.sleep(forTimeInterval: seconds) }

    private func tab(_ name: String) {
        let item = app.tabBars.buttons[name]
        need(item, "tab \(name)")
        item.tap()
        settle()
    }

    private func openDrawer() {
        let menu = app.buttons["Open sidebar"]
        need(menu, "Open sidebar")
        menu.tap()
        settle()
    }

    private func closeDrawer() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
        settle()
    }

    /// Scrolls the page's scroll view to its end, shoots it, and scrolls back to the top.
    private func scrollToEnd(_ name: String) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 { scroll.swipeUp(velocity: .fast) }
        settle()
        shot(name)
        for _ in 0..<8 { scroll.swipeDown(velocity: .fast) }
        settle()
    }

    private func launch() {
        app.launch()
        if !app.tabBars.firstMatch.waitForExistence(timeout: 60) {
            shot("connecting-stuck")
            XCTFail("tab bar never appeared within 60 s")
            return
        }
        settle(3)
    }

    func testConnectingScreen() {
        app.launchArguments = ["-holdConnecting"]
        app.launch()
        settle(2)
        let mark = app.staticTexts["connecting-wordmark"]
        need(mark, "connecting wordmark", timeout: 10)
        shot("connecting")
        let note = XCTAttachment(string: "screen=\(app.windows.firstMatch.frame) mark=\(mark.frame)")
        note.name = "connecting-frames"
        note.lifetime = .keepAlways
        add(note)
    }

    func testTour() {
        launch()
        pages(suffix: "")
    }

    func testDark() {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }
        launch()
        pages(suffix: "-dark")
    }

    private func pages(suffix: String) {
        let dark = !suffix.isEmpty
        tab("Chats")
        shot("chats-list\(suffix)")
        if !dark {
            let card = app.buttons["chat-card"].firstMatch
            need(card, "first chat card")
            card.tap()
            settle(3)
            shot("chat-thread")
            scrollToEnd("chat-thread-end")
            tab("Chats")
            settle()
        }
        if !dark { scrollToEnd("chats-list-end") }
        openDrawer()
        shot("chats-drawer\(suffix)")
        closeDrawer()

        tab("Planner")
        shot("planner-day\(suffix)")
        if !dark { scrollToEnd("planner-day-end") }
        openDrawer()
        shot("planner-drawer\(suffix)")
        if !dark {
            app.segmentedControls.buttons["Week"].tap()
            settle(2)
            shot("planner-week")
            openDrawer()
            app.segmentedControls.buttons["Month"].tap()
            settle(2)
            shot("planner-month")
            openDrawer()
            let checklist = app.buttons["Checklist"].firstMatch
            need(checklist, "Checklist row")
            checklist.tap()
            settle(2)
            shot("planner-checklist")
            openDrawer()
            let timeline = app.buttons["Timeline"].firstMatch
            need(timeline, "Timeline row")
            timeline.tap()
            settle()
            openDrawer()
            app.segmentedControls.buttons["Day"].tap()
            settle()
        } else {
            closeDrawer()
        }

        tab("Ghar")
        shot("ghar\(suffix)")
        tab("Chaavi")
        shot("chaavi\(suffix)")
        tab("System")
        shot("system\(suffix)")
        app.swipeUp()
        settle()
        shot("system-lower\(suffix)")
    }
}
