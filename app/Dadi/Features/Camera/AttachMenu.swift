import SwiftUI

extension ThreadAttach {
    /// The sources a message can take photos from, in the order the menu lists them.
    static let options: [ThreadAttach] = [.camera, .library]

    var title: String {
        switch self {
        case .camera: "Camera"
        case .library: "Photos"
        }
    }

    var symbol: String {
        switch self {
        case .camera: "camera"
        case .library: "photo.on.rectangle"
        }
    }
}

/// The plus's menu: a native popover anchored to `label` listing each photo source. Opening it leaves the
/// keyboard and the focused field alone.
struct AttachMenu<Plus: View>: View {
    /// Called with the source the person chose.
    let choose: (ThreadAttach) -> Void
    @ViewBuilder let label: Plus

    var body: some View {
        Menu {
            ForEach(ThreadAttach.options, id: \.self) { source in
                Button { choose(source) } label: { Label(source.title, systemImage: source.symbol) }
            }
        } label: {
            label
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Add a photo")
    }
}
