import SwiftUI

/// What an opening wake shows until all of it has been read: the lane filter, a message, a turn with its
/// thinking and calls, and a reply, in the shapes the entries will take.
struct WakeSkeleton: View {
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            bar(width: 170, height: 28, radius: 14)
            VStack(alignment: .leading, spacing: 4) {
                bar(width: 90, height: 10, radius: 5)
                bar(width: 230, height: 44, radius: 14)
            }
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(Color.rule).frame(width: 1)
                VStack(alignment: .leading, spacing: 8) {
                    bar(width: 80, height: 10, radius: 5)
                    bar(width: nil, height: 12, radius: 6)
                    bar(width: 200, height: 12, radius: 6)
                    bar(width: 140, height: 12, radius: 6)
                    bar(width: 180, height: 12, radius: 6)
                }
            }
            VStack(alignment: .trailing, spacing: 4) {
                bar(width: 70, height: 10, radius: 5)
                bar(width: 200, height: 32, radius: 14)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .opacity(dim ? 0.5 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Motion.breath) { dim = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading wake")
    }

    private func bar(width: CGFloat?, height: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.sageLine.opacity(0.3))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}
