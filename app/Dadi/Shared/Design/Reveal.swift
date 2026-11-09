import SwiftUI

/// A layout that gives its one child `progress` of its height, so content can open and close without a jump.
private struct RevealLayout: Layout {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(proposal)
        return CGSize(width: size.width, height: size.height * progress)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

/// Opens from nothing to its full height while fading in, and closes the same way.
struct RevealTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        RevealLayout(progress: phase.isIdentity ? 1 : 0) {
            content.opacity(phase.isIdentity ? 1 : 0)
        }
        .clipped()
    }
}

extension Transition where Self == RevealTransition {
    /// Height and opacity, as a disclosure opens and closes.
    static var reveal: RevealTransition { RevealTransition() }
}

/// Animates what changes under it when `value` changes, with the app's settle animation; none when Reduce Motion is on.
private struct RevealAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : Motion.settle, value: value)
    }
}

extension View {
    /// Settles the layout and any `.reveal` transition beneath this view whenever `value` changes, unless Reduce Motion is on.
    func reveals<Value: Equatable>(on value: Value) -> some View {
        modifier(RevealAnimation(value: value))
    }
}

/// Content that arrives whole: until `ready` the skeleton stands in its place, then the skeleton closes as all of
/// the content opens in one pass, so nothing appears piece by piece. Content ready on first draw is shown as it is.
struct Arrive<Skeleton: View, Content: View>: View {
    /// True once everything the content needs has been read.
    let ready: Bool
    /// What stands in the content's place until it is ready, shaped like it.
    @ViewBuilder let skeleton: () -> Skeleton
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if ready {
                content().transition(.reveal)
            } else {
                skeleton().transition(.reveal)
            }
        }
        .reveals(on: ready)
    }
}
