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
