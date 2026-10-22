import SwiftUI

/// dadi for iPhone. The root moves through Join, Connecting and Home as the
/// connection changes, carrying the દાદી wordmark between them, and the app
/// relays for the watch app.
@main
struct DadiApp: App {
    @State private var connection: Connection
    @State private var relay: WatchRelay
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var wordmark

    init() {
        let connection = Connection()
        _connection = State(initialValue: connection)
        let relay = WatchRelay(connection: connection)
        relay.activate()
        _relay = State(initialValue: relay)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                switch connection.state {
                case .needsSetup:
                    JoinView(connection: connection, wordmark: wordmark)
                        .transition(.opacity)
                case .connecting, .failed:
                    ConnectingView(connection: connection, wordmark: wordmark)
                        .transition(.opacity)
                case .online:
                    if let services = connection.services {
                        HomeView(services: services, wordmark: wordmark)
                            .transition(.opacity)
                    }
                }
            }
            .animation(Motion.settle, value: connection.state)
            .task {
                connection.start()
                await connection.watch()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                connection.refresh()
                Task { await relay.push() }
            }
        }
    }
}
