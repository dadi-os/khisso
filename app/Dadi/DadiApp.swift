import SwiftUI

/// dadi for iPhone and Mac. The root shows Join until this device has a setup
/// code, then Home once Hath answers.
@main
struct DadiApp: App {
    @State private var connection = Connection()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                switch connection.state {
                case .needsSetup:
                    JoinView(connection: connection)
                case .connecting(let detail):
                    ContentUnavailableView {
                        Label("Connecting to dadi", systemImage: "network")
                    } description: {
                        Text(detail ?? "Logging in to your box.")
                    } actions: {
                        Button("Forget this device", role: .destructive) { connection.forget() }
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Can't reach dadi", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") { connection.retry() }
                            .buttonStyle(.glassProminent)
                        Button("Forget this device", role: .destructive) { connection.forget() }
                    }
                case .online:
                    if let hath = connection.hath {
                        HomeView(hath: hath, nodeName: connection.nodeName)
                    }
                }
            }
            .task { connection.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { connection.refresh() }
            }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        #endif
    }
}
