import SwiftUI

/// dadi for iPhone and Mac. The root moves through Join, Connecting and Home
/// as the connection changes, carrying the દાદી wordmark between them. On the
/// iPhone it also relays for the watch app.
@main
struct DadiApp: App {
    @State private var connection: Connection
    #if os(iOS)
    @State private var relay: WatchRelay
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var wordmark

    init() {
        let connection = Connection()
        _connection = State(initialValue: connection)
        #if os(iOS)
        let relay = WatchRelay(connection: connection)
        relay.activate()
        _relay = State(initialValue: relay)
        #endif
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
                        HomeView(services: services, nodeName: connection.nodeName, wordmark: wordmark)
                            .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    }
                }
            }
            .animation(Motion.settle, value: connection.state)
            .task { connection.start() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                connection.refresh()
                #if os(iOS)
                Task { await relay.push() }
                #endif
            }
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands { GoCommands() }
        #endif
    }
}
