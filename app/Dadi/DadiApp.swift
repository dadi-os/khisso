import SwiftUI

/// dadi for iPhone and Mac. The root moves through Join, Connecting and Home
/// as the connection changes, carrying the દાદી wordmark between them.
@main
struct DadiApp: App {
    @State private var connection = Connection()
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var wordmark

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
                    if let hath = connection.hath {
                        HomeView(hath: hath, nodeName: connection.nodeName, wordmark: wordmark)
                            .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    }
                }
            }
            .animation(Motion.settle, value: connection.state)
            .task { connection.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { connection.refresh() }
            }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        #endif
    }
}
