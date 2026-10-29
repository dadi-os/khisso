import SwiftUI

/// What the app calls each lane wherever a lane is named, as in thaali: the
/// process lane is the agent reading what arrived and answering it, the work
/// lane is it doing the job in the background.
extension Lane {
    var label: String {
        switch self {
        case .process: "processing"
        case .work: "working"
        }
    }
}

/// Thaali's processing mark: three dots flowing left to right, each swelling in
/// at the left, drifting right, then dipping and fading off the end to come
/// back at the start. Reduced motion holds them still mid-flow.
struct ProcessingMark: View {
    /// How much larger than thaali's 22 × 12 mark to draw it.
    var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 22, height: 12)
    static let dot: CGFloat = 3.5
    /// One pass of a dot across the mark, in milliseconds.
    static let flow: Double = 1500

    /// Where dot `index` (of three) is `ms` into the flow: its center, scale
    /// and opacity.
    static func pose(_ index: Int, ms: Double) -> (center: CGPoint, scale: CGFloat, opacity: Double) {
        let p = (ms / flow + Double(index) / 3).truncatingRemainder(dividingBy: 1)
        let rise = sin(.pi * p)
        let drop = p > 0.72 ? pow((p - 0.72) / 0.28, 2) : 0
        return (CGPoint(x: 2 + p * (size.width - 4), y: size.height / 2 + drop * 4), 0.55 + 0.45 * rise, rise)
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let ms = reduceMotion ? Self.flow * 0.3 : context.date.timeIntervalSinceReferenceDate * 1000
            Canvas { canvas, _ in
                canvas.scaleBy(x: scale, y: scale)
                for index in 0..<3 {
                    let pose = Self.pose(index, ms: ms)
                    let r = Self.dot / 2 * pose.scale
                    canvas.fill(
                        Circle().path(in: CGRect(x: pose.center.x - r, y: pose.center.y - r, width: r * 2, height: r * 2)),
                        with: .color(.sageDeep.opacity(pose.opacity))
                    )
                }
            }
        }
        .frame(width: Self.size.width * scale, height: Self.size.height * scale)
        .accessibilityHidden(true)
    }
}

/// Thaali's working sheen: one turning angle drives a beam of light sweeping
/// through the surface and a ring of light running round its edge, so a busy
/// pill or row reads as working at the level of the surface itself.
private struct LaneSheen<S: InsettableShape>: ViewModifier {
    let active: Bool
    let shape: S
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One turn, in seconds.
    private let turn = 2.4

    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation(paused: reduceMotion)) { context in
                let seconds = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                let angle = Angle.degrees(seconds.truncatingRemainder(dividingBy: turn) / turn * 360 - 90)
                content
                    .background {
                        shape.fill(gradient(from: angle, peak: 0.2, clearUntil: 0.62))
                    }
                    .overlay {
                        shape.strokeBorder(gradient(from: angle, peak: 0.9, clearUntil: 0.58), lineWidth: 1)
                    }
                    .clipShape(shape)
            }
        } else {
            content
        }
    }

    private func gradient(from angle: Angle, peak: Double, clearUntil: Double) -> AngularGradient {
        AngularGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: clearUntil),
                .init(color: .sage.opacity(peak), location: 0.84),
                .init(color: .clear, location: 1),
            ],
            center: .center,
            startAngle: angle,
            endAngle: angle + .degrees(360)
        )
    }
}

extension View {
    /// Runs thaali's working sheen across `shape` while `active`.
    func laneSheen<S: InsettableShape>(_ active: Bool, in shape: S) -> some View {
        modifier(LaneSheen(active: active, shape: shape))
    }
}

/// Thaali's lane pill: soft glass floating above the composer while a lane is
/// busy, the one place a thread shows what its agent is doing. Processing plays
/// the flowing dots inside the pill, working runs the sheen on the pill
/// itself, and both play together when both lanes run.
struct LaneChip: View {
    let lanes: Set<Lane>
    /// The glass namespace shared with whatever splits off from the pill (the
    /// scroll-to-newest caret), so the two flow apart and back as one glass.
    let glass: Namespace.ID

    /// The pill's height, which the caret beside it matches.
    static let height: CGFloat = 36

    var body: some View {
        ZStack {
            if let label {
                let processing = lanes.contains(.process)
                HStack(spacing: 10) {
                    if processing {
                        ProcessingMark(scale: 1.35)
                            .transition(.opacity.combined(with: .scale(scale: 0.2, anchor: .leading)))
                    }
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(0.3)
                        .foregroundStyle(.sageText)
                        .id(label)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 3)),
                            removal: .opacity.combined(with: .offset(y: -3))
                        ))
                }
                .padding(.leading, processing ? 13 : 17)
                .padding(.trailing, 17)
                .frame(height: Self.height)
                .overlay(Capsule().strokeBorder(Color.sageLine.opacity(0.48), lineWidth: 1))
                .laneSheen(lanes.contains(.work), in: Capsule())
                .glassEffect(.regular.tint(Color.bone.opacity(0.6)), in: .capsule)
                .glassEffectID("lane", in: glass)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(Motion.settle, value: lanes)
        .allowsHitTesting(false)
    }

    /// "processing", "working", or "processing + working".
    private var label: String? {
        let named = [Lane.process, .work].filter(lanes.contains).map(\.label)
        return named.isEmpty ? nil : named.joined(separator: " + ")
    }
}
