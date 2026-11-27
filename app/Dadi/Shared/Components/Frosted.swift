import SwiftUI

extension View {
    /// A material and the surface colour behind `shape`, thick enough that text scrolling under it cannot be read, for glass
    /// that floats over content (the composer, a quote, the menu button and the name capsule). Put it under the glass effect.
    func frostedBacking<S: Shape>(_ shape: S) -> some View {
        background {
            shape.fill(.regularMaterial)
            shape.fill(Color.bone.opacity(0.75))
        }
    }
}
