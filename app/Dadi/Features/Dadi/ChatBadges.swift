import SwiftUI

/// A conversation's unread count: a capsule of sage-tinted Liquid Glass with the count in bone.
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(Color.bone)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .glassEffect(.regular.tint(Color.sageDeep.opacity(0.85)), in: .capsule)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("\(count) unread")
    }
}

/// The sage dot that opens a row while an agent lane runs: a 14 pt dot with a ring that spreads
/// and fades around it, large enough to read at a glance.
struct WorkingDot: View {
    private static let size: CGFloat = 14

    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.sage, lineWidth: 2)
                .scaleEffect(pulsing ? 2 : 1)
                .opacity(pulsing ? 0 : 0.7)
            Circle().fill(Color.sageDeep)
        }
        .frame(width: Self.size, height: Self.size)
        .padding(.horizontal, 3)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulsing = true }
        }
        .accessibilityLabel("Working")
    }
}
