import UIKit
import os

/// Which interface orientations each tab allows: portrait everywhere, landscape only on the Planner, where it shows the
/// Week.
enum OrientationPolicy {
    /// The orientations `tab` allows.
    static func mask(for tab: HomeView.Tab) -> UIInterfaceOrientationMask {
        tab == .planner ? .allButUpsideDown : .portrait
    }
}

/// The orientations the app delegate answers with, set by Home as the selected tab changes.
@MainActor
enum AppOrientation {
    private static let log = Logger(subsystem: "app.dadi", category: "orientation")
    private(set) static var allowed = UIInterfaceOrientationMask.portrait

    /// Allows `mask`; a screen already turned to an orientation outside it is turned back to portrait.
    static func allow(_ mask: UIInterfaceOrientationMask) {
        allowed = mask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        guard !mask.contains(scene.effectiveGeometry.interfaceOrientation.mask) else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
            log.error("could not turn back to portrait: \(error.localizedDescription)")
        }
    }
}

extension UIInterfaceOrientation {
    var mask: UIInterfaceOrientationMask {
        switch self {
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        case .portraitUpsideDown: .portraitUpsideDown
        default: .portrait
        }
    }
}

/// Answers which orientations a window supports from `AppOrientation`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { AppOrientation.allowed }
    }
}
