import Foundation
import Testing
import UIKit
@testable import Khisso

private func login(_ uris: [String], type: String = "login") -> ChaaviItem {
    ChaaviItem(id: "1", name: "n", favorite: false, folderId: nil, type: type, login: .init(username: nil, uris: uris.map { .init(uri: $0) }, hasPassword: true, hasTotp: false))
}

/// The domain Chaavi's icon proxy is asked about comes from the first login website only.
struct SiteDomainTests {
    @Test func takesTheHostOfTheFirstWebsiteWithoutSchemeWwwOrPort() {
        #expect(login(["https://www.GitHub.com/login", "other.example"]).siteDomain == "github.com")
        #expect(login(["dash.cloudflare.example:8443/x"]).siteDomain == "dash.cloudflare.example")
        #expect(login(["apple.com"]).siteDomain == "apple.com")
    }

    @Test func isNilWithoutAWebsiteOrADomainName() {
        #expect(login([]).siteDomain == nil)
        #expect(login(["https://x.com"], type: "note").siteDomain == nil)
        #expect(login(["androidapp://com.example.app"]).siteDomain == nil)
        #expect(login(["192.168.1.5"]).siteDomain == nil)
        #expect(login(["localhost"]).siteDomain == nil)
        #expect(login([""]).siteDomain == nil)
    }

    @Test func iconsAreAskedOfChaaviItself() {
        #expect(ChaaviClient.iconPath("github.com") == "/icons/github.com/icon.png")
        #expect(ChaaviClient.vaultURL.host() == "chaavi.dadi")
    }
}

/// Icons are fetched once per domain; the proxy's generic image and a failure both mean no icon.
@MainActor
struct SiteIconsTests {
    private final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [String] = []
        func add(_ domain: String) { lock.withLock { list.append(domain) } }
        var all: [String] { lock.withLock { list } }
    }

    @Test func servesTheIconAndAsksOncePerDomain() async {
        let asked = Asked()
        let icons = SiteIcons { domain in
            asked.add(domain)
            return Data(domain == ChaaviClient.noIconDomain ? "generic".utf8 : "octocat".utf8)
        }
        #expect(await icons.icon(for: "github.com") == Data("octocat".utf8))
        #expect(await icons.icon(for: "github.com") == Data("octocat".utf8))
        #expect(asked.all.filter { $0 == "github.com" }.count == 1)
    }

    @Test func theGenericImageIsNoIcon() async {
        let icons = SiteIcons { _ in Data("generic".utf8) }
        #expect(await icons.icon(for: "unknown.example") == nil)
    }

    @Test func aFailedReadIsNoIconAndIsAskedAgain() async {
        struct Down: Error {}
        let asked = Asked()
        let icons = SiteIcons { domain in
            asked.add(domain)
            throw Down()
        }
        #expect(await icons.icon(for: "github.com") == nil)
        #expect(await icons.icon(for: "github.com") == nil)
        #expect(asked.all.filter { $0 == "github.com" }.count == 2)
    }
}

/// The breadcrumb lists every place from the top, and gathers the middle of a long path.
struct BreadcrumbTests {
    private func titles(_ scope: String?) -> [String] {
        Breadcrumb.pieces(scope: scope, root: "All items").map {
            switch $0 {
            case .segment(let segment): segment.title
            case .hidden(let hidden): "…" + hidden.map(\.title).joined(separator: ",")
            }
        }
    }

    @Test func theTopIsJustTheRoot() {
        #expect(titles(nil) == ["All items"])
    }

    @Test func listsEachFolderOfTheScope() {
        #expect(titles("Banking/Chase") == ["All items", "Banking", "Chase"])
    }

    @Test func segmentsBrowseTheirOwnPath() {
        let all = Breadcrumb.segments(scope: "A/B/C", root: "All items")
        #expect(all.map(\.path) == [nil, "A", "A/B", "A/B/C"])
    }

    @Test func aLongPathKeepsFirstAndLastTwoAndGathersTheMiddle() {
        #expect(titles("A/B/C/D/E") == ["All items", "…A,B,C", "D", "E"])
        let pieces = Breadcrumb.pieces(scope: "A/B/C/D/E", root: "All items")
        guard case .hidden(let hidden) = pieces[1] else { Issue.record("no gathered middle"); return }
        #expect(hidden.map(\.path) == ["A", "A/B", "A/B/C"])
    }

    @Test func aPathAtCapacityIsNotGathered() {
        #expect(titles("A/B/C") == ["All items", "A", "B", "C"])
    }
}

/// System leaves asleep helper tasks out of its list and counts.
struct SystemTasksTests {
    private func task(_ id: String, _ status: String, at: String) throws -> NasTask {
        let json = #"{"task":"task/browser/\#(id)","kind":"browser","owner":"a","purpose":"p","status":"\#(status)","resource":null,"state":"s","last_activity":"\#(at)"}"#
        return try ServiceJSON.decoder.decode(NasTask.self, from: Data(json.utf8))
    }

    @MainActor
    @Test func dropsAsleepAndKeepsTheRestNewestFirst() throws {
        let all = [
            try task("old", "working", at: "2026-11-09T09:00:00Z"),
            try task("zz", "asleep", at: "2026-11-09T12:00:00Z"),
            try task("new", "stopped", at: "2026-11-09T11:00:00Z"),
            try task("mid", "asking", at: "2026-11-09T10:00:00Z"),
            try task("p", "paused", at: "2026-11-09T08:00:00Z"),
            try task("i", "idle", at: "2026-11-09T07:00:00Z"),
        ]
        #expect(SystemStore.awake(all).map(\.status) == ["stopped", "asking", "working", "paused", "idle"])
    }
}

/// Facts and situation lines of the sheets rebuilt on the shared anatomy.
@MainActor
struct SheetContentTests {
    private func device(online: Bool, on: Bool?, brightness: Double?) throws -> GharDevice {
        let state = [on.map { #""on":{"value":\#($0)}"# }, brightness.map { #""brightness":{"value":\#($0)}"# }].compactMap { $0 }.joined(separator: ",")
        let json = #"{"id":"d","name":"Desk lamp","kind":"light","tags":[],"capabilities":[{"capability":"on_off","config":{}},{"capability":"level","config":{}}],"online":\#(online),"state":{\#(state)}}"#
        return try JSONDecoder().decode(GharDevice.self, from: Data(json.utf8))
    }

    @Test func aLightsSituationIsItsStateAndBrightness() throws {
        #expect(LightSheet.situation(try device(online: true, on: true, brightness: 80)).text == "On · 80%")
        #expect(LightSheet.situation(try device(online: true, on: false, brightness: 80)).text == "Off")
        let offline = LightSheet.situation(try device(online: false, on: true, brightness: 80))
        #expect(offline.text == "Unreachable" && offline.tone == .late)
    }

    @Test func thePickerHeaderCountsWhatIsChosen() {
        #expect(DevicePicker.summary(chosen: 0) == "Choose lights")
        #expect(DevicePicker.summary(chosen: 1) == "1 light chosen")
        #expect(DevicePicker.summary(chosen: 3) == "3 lights chosen")
    }

    private func task(status: String, state: String, url: String? = nil) throws -> NasTask {
        let active = url.map { #","active_url":"\#($0)""# } ?? ""
        let json = #"{"task":"task/browser/3","kind":"browser","owner":"cse","purpose":"Check grades","status":"\#(status)","resource":"1","state":"\#(state)","last_activity":"2026-11-09T10:00:00Z"\#(active)}"#
        return try ServiceJSON.decoder.decode(NasTask.self, from: Data(json.utf8))
    }

    @Test func aTaskSheetListsOnlyTrueFacts() throws {
        let working = try task(status: "working", state: "Opening the page", url: "https://a.dev/x")
        #expect(TaskSheet.facts(of: working, owner: "CSE").map(\.label) == ["Agent", "Task", "Now", "Page", "Last active"])
        let asking = try task(status: "asking", state: "Which term?")
        #expect(TaskSheet.facts(of: asking, owner: "CSE").map(\.label) == ["Agent", "Task", "Last active"])
        #expect(TaskSheet.situation(of: asking, owner: "CSE").text == "Waiting on CSE")
    }

    @Test func theAgentRailLeadsWithReplyOrOpenThreadAndOffersStopOnlyWhenThereIsSomethingToStop() {
        func titles(replying: Bool, stoppable: Bool, stopping: Bool = false) -> [String] {
            AgentSheet.rail(replying: replying, stoppable: stoppable, stopping: stopping, openThread: {}, toggleStop: {}).map {
                if case .action(let title, _, _, _) = $0 { title } else { "" }
            }
        }
        #expect(titles(replying: true, stoppable: false) == ["Reply"])
        #expect(titles(replying: false, stoppable: true) == ["Open thread", "Stop"])
        #expect(titles(replying: false, stoppable: false, stopping: true) == ["Open thread", "Stopping…"])
    }
}

/// A thread's viewfinder attaches its several-photo pictures however it is closed.
@MainActor
struct ThreadDraftCameraTests {
    private func photo() -> DraftFile {
        DraftFile(name: "photo.jpg", mediaType: "image/jpeg", url: URL(filePath: "/tmp/photo.jpg"))
    }

    @Test func closingTheViewfinderAttachesWhatWasTaken() {
        let draft = ThreadDraft()
        draft.attaching = .camera
        draft.shots.toggle()
        _ = draft.shots.take(photo())
        _ = draft.shots.take(photo())
        #expect(draft.files.isEmpty)
        draft.attaching = nil
        #expect(draft.files.count == 2)
        #expect(draft.shots.held.isEmpty)
    }

    @Test func switchingToTheLibraryClosesTheViewfinderAndKeepsThePictures() {
        let draft = ThreadDraft()
        draft.attaching = .camera
        draft.shots.toggle()
        _ = draft.shots.take(photo())
        draft.attaching = .library
        #expect(draft.files.count == 1)
    }

    @Test func openingTheViewfinderDropsNothing() {
        let draft = ThreadDraft()
        draft.attaching = .camera
        draft.shots.toggle()
        _ = draft.shots.take(photo())
        draft.attaching = .camera
        #expect(draft.files.isEmpty && draft.shots.held.count == 1)
    }
}
