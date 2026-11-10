import SwiftUI

/// Sizes a sheet to its content, so a short card opens just as tall as it is
/// instead of half the screen with empty space under it. The content sits in a
/// scroll view that only scrolls when the content is taller than the sheet can
/// be (a small phone, a larger text size, a long note), so nothing is cut off.
private struct FittedSheet: ViewModifier {
    @State private var height: CGFloat = 320

    func body(content: Content) -> some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height)])
    }
}

extension View {
    /// Opens this sheet at its content's height, scrolling when that is taller than the screen allows.
    func fittedSheet() -> some View {
        modifier(FittedSheet())
    }
}
