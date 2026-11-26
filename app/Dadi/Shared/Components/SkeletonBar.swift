import SwiftUI

/// One loading bar in the look of `SkeletonRows`, sized by its caller so a view can lay out the shape of what is
/// coming: a rounded bar a light sweeps across, still under Reduce Motion.
struct SkeletonBar: View {
    var radius: CGFloat = 10

    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.sageLine.opacity(0.28))
            .overlay {
                LinearGradient(colors: [.clear, Color.sageLine.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                    .offset(x: sweep ? 320 : -320)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) { sweep = true }
            }
            .accessibilityHidden(true)
    }
}
