import SwiftUI

/// dadi for iPhone. The root moves through Join, Connecting and Home as the
/// connection changes, carrying the દાદી wordmark from Join to Connecting, and the app
/// relays for the watch app.
@main
struct DadiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var connection: Connection
    @State private var relay: WatchRelay
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var wordmark
    /// An unstarted connection that `-holdConnecting` (debug builds) shows the Connecting screen for.
    @State private var held = Connection()
    private var holding: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-holdConnecting")
        #else
        false
        #endif
    }

    init() {
        let connection = Connection()
        _connection = State(initialValue: connection)
        let relay = WatchRelay(connection: connection)
        relay.activate()
        _relay = State(initialValue: relay)
        UITabBarItem.appearance().badgeColor = UIColor(Color.sageDeep)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                switch holding ? held.state : connection.state {
                case .needsSetup:
                    JoinView(connection: connection, wordmark: wordmark)
                        .transition(.opacity)
                case .connecting, .failed:
                    if let services = connection.services, let since = connection.offlineSince {
                        HomeView(services: services, online: false)
                            .saturation(0.5)
                            .overlay(alignment: .top) {
                                OfflinePill(since: since)
                                    .padding(.top, 4)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                    } else {
                        ConnectingView(connection: holding ? held : connection, wordmark: wordmark)
                            .transition(.opacity)
                    }
                case .online:
                    if let services = connection.services {
                        HomeView(services: services, online: true)
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
