import SwiftUI

/// dadi on the wrist: Talk to Dadi, today's plan, the agents and the box,
/// four pages turned with the Digital Crown, on true black.
@main
struct DadiWatchApp: App {
    @State private var store = WatchStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        store.activate()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                DadiPage(store: store)
                TodayPage(snapshot: store.snapshot)
                AgentsPage(store: store)
                BoxPage(store: store)
            }
            .tabViewStyle(.verticalPage)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.refresh() }
            }
        }
    }
}
