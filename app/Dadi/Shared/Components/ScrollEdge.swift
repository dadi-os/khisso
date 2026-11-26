import SwiftUI

/// Where a `ScrollEdge` sits against its container.
enum ScrollEdgeSide {
    case top
    case bottom
}

/// The scroll-edge effect behind floating glass, thaali's: content scrolling toward the edge is blurred
/// progressively and dissolves into the surface with no line where the effect ends. A veil of the surface colour
/// (alpha .34 at the edge, .21 at 38 %, .08 at 72 %, 0 at the far side) sits over stacked materials whose masks ramp
/// from nothing to full toward the edge. Reduce Transparency swaps it for a solid .94 veil without blur; the effect is meant to be barely noticeable. It takes no
/// touches and sits under the floating elements, which keep their own glass.
struct ScrollEdge: View {
    let side: ScrollEdgeSide
    /// Strip height: the floating elements' block plus 44 pt for the effect to dissolve in.
    let size: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// A thread's strips: the back button and name capsule block (68 pt) plus 44, and the composer with the activity pill plus 44.
    static let threadTop: CGFloat = 112
    static let threadBottom: CGFloat = 148
    /// The chat list's strips: the search row, and the dock.
    static let listTop: CGFloat = 88
    static let listBottom: CGFloat = 116

    /// The veil's alpha stops, from the edge inward.
    static let veil: [(location: CGFloat, alpha: Double)] = [(0, 0.34), (0.38, 0.21), (0.72, 0.08), (1, 0)]

    /// Thaali's five blur layers (0.4, 0.8, 1.4, 2.2 and 3.5 px at most), each as a share of the strongest and how far
    /// across the strip it reaches, from the edge: material cannot take a radius, so a layer's strength is its opacity.
    static let layers: [(strength: Double, reach: CGFloat)] = [(0.11, 1), (0.23, 0.8), (0.4, 0.6), (0.63, 0.4), (1, 0.22)]

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color.bone.opacity(0.94).mask(fade(from: 1, to: 0))
            } else {
                ForEach(Self.layers.indices, id: \.self) { index in
                    Rectangle().fill(.ultraThinMaterial).opacity(Self.layers[index].strength * 0.5).mask(fade(from: 1, to: 0, reach: Self.layers[index].reach))
                }
                LinearGradient(stops: Self.veil.map { .init(color: Color.bone.opacity($0.alpha), location: $0.location) }, startPoint: start, endPoint: end)
            }
        }
        .frame(height: size)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: side == .top ? .top : .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var start: UnitPoint { side == .top ? .top : .bottom }
    private var end: UnitPoint { side == .top ? .bottom : .top }

    /// A mask that is `from` opaque at the edge and `to` at `reach` of the way in, clear beyond.
    private func fade(from: Double, to: Double, reach: CGFloat = 1) -> some View {
        LinearGradient(stops: [.init(color: .black.opacity(from), location: 0), .init(color: .black.opacity(to), location: reach), .init(color: .clear, location: reach + 0.0001)], startPoint: start, endPoint: end)
    }
}

extension View {
    /// Lays the scroll-edge effect over the view's top or bottom, under whatever floats there.
    func scrollEdge(_ side: ScrollEdgeSide, size: CGFloat) -> some View {
        overlay(alignment: side == .top ? .top : .bottom) { ScrollEdge(side: side, size: size) }
    }
}
