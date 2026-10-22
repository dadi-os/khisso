import SwiftUI

/// Sizes a sheet to its content, so a short card opens just as tall as it is
/// instead of half the screen with empty space under it.
private struct FittedSheet: ViewModifier {
    @State private var height: CGFloat = 320

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .presentationDetents([.height(height)])
    }
}

extension View {
    /// Opens this sheet at its content's height.
    func fittedSheet() -> some View {
        modifier(FittedSheet())
    }
}
