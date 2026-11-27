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
        let item = app.tabBars.buttons[name].firstMatch
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
        let forget = app.buttons["connecting-forget"]
        need(forget, "Forget this device button", timeout: 15)
        let shown = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: forget)
        wait(for: [shown], timeout: 20)
        settle(1)
        shot("connecting-forget")
        let note = XCTAttachment(string: "screen=\(app.windows.firstMatch.frame) mark=\(mark.frame) forget=\(forget.frame) hittable=\(forget.isHittable)")
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

    private func chooseMode(_ mode: String, shotMenu: Bool = false) {
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Planner view'")).firstMatch
        need(chip, "Planner view chip")
        chip.tap()
        settle()
        if shotMenu { shot("planner-mode-menu") }
        let item = app.buttons[mode].firstMatch
        need(item, "\(mode) menu item")
        item.tap()
    }

    private func pages(suffix: String) {
        let dark = !suffix.isEmpty
        tab("Chats")
        shot("chats-list\(suffix)")
        if !dark {
            let talk = app.buttons["Talk to Dadi"].firstMatch
            need(talk, "Talk to Dadi bar", timeout: 5)
            talk.tap()
            settle(1)
            shot("chats-keyboard")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            settle()
        }
        if !dark {
            let card = app.buttons["chat-card"].firstMatch
            need(card, "first chat card")
            card.tap()
            for frame in 1...5 { shot("chat-push-\(frame)") }
            settle(3)
            shot("chat-thread")
            for _ in 0..<2 { app.scrollViews.firstMatch.swipeDown(velocity: .fast) }
            settle()
            shot("chat-thread-scrolled-up")
            for _ in 0..<2 { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
            settle()
            shot("chat-thread-scrolled-down")
            scrollToEnd("chat-thread-end")
            let held = app.scrollViews.firstMatch.staticTexts.allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > 250 && $0.frame.maxY < 600 }
            need(held ?? app.staticTexts.firstMatch, "a message in the middle of the thread", timeout: 5)
            held?.press(forDuration: 1.2)
            settle()
            shot("thread-hold-menu")
            let reply = app.buttons["Reply"].firstMatch
            need(reply, "Reply in the held message's menu", timeout: 5)
            reply.tap()
            settle()
            shot("thread-quote")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            settle()
            let bar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Message '")).firstMatch
            need(bar, "the thread's message bar in the dock", timeout: 5)
            bar.tap()
            settle(1)
            shot("thread-keyboard")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            settle()
            app.scrollViews.firstMatch.swipeRight()
            settle()
            shot("thread-swipe-message")
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            edge.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
            settle()
            shot("thread-edge-swipe")
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
        closeDrawer()
        chooseMode("Month", shotMenu: !dark)
        settle(2)
        shot("planner-month\(suffix)")
        let bare = app.buttons.matching(NSPredicate(format: "label MATCHES '^[A-Za-z]+day, [A-Za-z]+ [0-9]+$'")).allElementsBoundByIndex.first { $0.isHittable }
        guard let bare else { return XCTFail("no hittable month day") }
        bare.tap()
        settle()
        shot("planner-month-empty\(suffix)")
        XCUIDevice.shared.orientation = .landscapeLeft
        settle(3)
        shot("planner-week-landscape\(suffix)")
        XCUIDevice.shared.orientation = .portrait
        settle(3)
        let openDay = app.buttons["Open day"].firstMatch
        need(openDay, "Open day")
        openDay.tap()
        settle(2)
        shot("planner-day-empty\(suffix)")
        openDrawer()
        let checklist = app.buttons["Checklist"].firstMatch
        need(checklist, "Checklist row")
        checklist.tap()
        settle(2)
        shot("planner-checklist\(suffix)")
        openDrawer()
        let timeline = app.buttons["Timeline"].firstMatch
        need(timeline, "Timeline row")
        timeline.tap()
        settle()
        chooseMode("Day")
        settle()

        tab("Ghar")
        shot("ghar\(suffix)")
        if !dark {
            XCUIDevice.shared.orientation = .landscapeLeft
            settle(2)
            shot("ghar-landscape-stays-portrait")
            XCUIDevice.shared.orientation = .portrait
            settle(2)
        }
        tab("Chaavi")
        shot("chaavi\(suffix)")
        tab("System")
        shot("system\(suffix)")
        app.swipeUp()
        settle()
        shot("system-lower\(suffix)")
    }
}
