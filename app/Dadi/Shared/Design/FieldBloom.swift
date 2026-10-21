import SwiftUI

/// The ground every dadi screen sits on: bone, with sage light pooling low on
/// the left and high on the right, as in thaali. The pools drift slowly;
/// Reduce Motion holds them still.
struct FieldBloom: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: points(at: t),
                colors: [
                    .bone, .bone, .sageLine.mix(with: .bone, by: 0.7),
                    .bone, .bone, .bone,
                    .sage.mix(with: .bone, by: 0.72), .boneRaised, .boneDeep,
                ]
            )
            .overlay {
                RadialGradient(colors: [.sageLine.opacity(0.22), .clear], center: bloomCenter(at: t), startRadius: 0, endRadius: 420)
                    .blendMode(.plusLighter)
                    .opacity(0.6)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Mesh control points that wander a few percent around a grid.
    private func points(at t: TimeInterval) -> [SIMD2<Float>] {
        func wobble(_ phase: Double, _ amount: Double) -> Float { Float(sin(t / 9 + phase) * amount) }
        return [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.5 + wobble(0, 0.08), 0.5 + wobble(1.7, 0.07)], [1, 0.5],
            [0, 1], [0.5 + wobble(2.4, 0.06), 1], [1, 1],
        ]
    }

    private func bloomCenter(at t: TimeInterval) -> UnitPoint {
        UnitPoint(x: 0.82 + sin(t / 11) * 0.05, y: 0.18 + cos(t / 13) * 0.04)
    }
}
