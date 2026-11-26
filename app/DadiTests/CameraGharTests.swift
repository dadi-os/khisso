import Foundation
import Testing
@testable import Khisso

/// The viewfinder attaches the first picture and closes unless the person asked for several.
struct CaptureBatchTests {
    @Test func singleModeAttachesTheFirstPictureAtOnce() {
        var batch = CaptureBatch<Int>()
        #expect(batch.take(1) == [1])
        #expect(batch.held.isEmpty)
    }

    @Test func multiModeHoldsPicturesUntilDone() {
        var batch = CaptureBatch<Int>()
        batch.toggle()
        #expect(batch.take(1) == nil)
        #expect(batch.take(2) == nil)
        #expect(batch.held == [1, 2])
        #expect(batch.finish() == [1, 2])
        #expect(batch.held.isEmpty)
    }

    @Test func switchingBackToSingleLosesNothing() {
        var batch = CaptureBatch<Int>()
        batch.toggle()
        _ = batch.take(1)
        batch.toggle()
        #expect(batch.mode == .single)
        #expect(batch.take(2) == [1, 2])
    }

    @Test func finishingWithNothingTakenAttachesNothing() {
        var batch = CaptureBatch<Int>()
        batch.toggle()
        #expect(batch.finish().isEmpty)
    }
}

/// The plus offers each photo source once, with its own words.
struct AttachMenuTests {
    @Test func listsCameraThenPhotosWithDistinctTitles() {
        #expect(ThreadAttach.options == [.camera, .library])
        #expect(Set(ThreadAttach.options.map(\.title)).count == ThreadAttach.options.count)
    }
}

/// A command to a device that does not answer is a toast naming it, not content on the page.
@MainActor
struct GharToastTests {
    private func device(_ name: String, online: Bool) throws -> GharDevice {
        let json = #"{"id":"\#(name)","name":"\#(name)","kind":"light","tags":[],"capabilities":[{"capability":"on_off","config":{}}],"online":\#(online),"state":{}}"#
        return try JSONDecoder().decode(GharDevice.self, from: Data(json.utf8))
    }

    @Test func switchingAnUnreachableDeviceToastsItsName() throws {
        let store = GharStore(ghar: GharClient(session: .shared))
        store.setOn(true, [try device("Desk lamp", online: false)])
        let toast = try #require(store.toaster.toasts.first)
        #expect(toast.failure)
        #expect(toast.title == "Desk lamp is unreachable")
    }

    @Test func aGroupWithOneDeviceAnsweringIsLeftQuiet() throws {
        let store = GharStore(ghar: GharClient(session: .shared))
        store.setOn(false, [try device("Desk lamp", online: false)])
        store.toaster.dismiss("ghar-unreachable")
        #expect(store.toaster.toasts.isEmpty)
    }

    @Test func namesWhoIsUnreachable() {
        #expect(GharStore.unreachableTitle(["Desk lamp"]) == "Desk lamp is unreachable")
        #expect(GharStore.unreachableTitle(["Desk lamp", "Hall"]) == "Desk lamp and Hall are unreachable")
        #expect(GharStore.unreachableTitle(["a", "b", "c"]) == "3 devices are unreachable")
    }

    @Test func aRefusalCarriesGharsReason() {
        let toast = GharStore.refusedToast([(name: "Hall", reason: "Matter said no")])
        #expect(toast.failure)
        #expect(toast.detail == "Matter said no")
    }
}

/// The connecting line shows Hath's progress words when it has them.
struct ConnectingStatusTests {
    @Test func prefersProgressWordsOverTheDefault() {
        #expect(ConnectingView.status(detail: "Logging in to your box…") == "Logging in to your box…")
        #expect(ConnectingView.status(detail: nil) == "Connecting to dadi")
    }
}
