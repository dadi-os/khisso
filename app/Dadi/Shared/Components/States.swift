import SwiftUI

/// The shared look for a view with nothing to show yet, matching thaali's
/// states: a still dashed ring, a caps label, and one quiet line.
struct EmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(Color.sageLine, style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                    .frame(width: 56, height: 56)
                Circle()
                    .strokeBorder(Color.sage, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
            }
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(.sageDeep)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.inkFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Loading rows in the shape of the list that is coming: rounded bars a light
/// sweeps across, still under Reduce Motion.
struct SkeletonRows: View {
    let count: Int
    /// Height of one row.
    var height: CGFloat = 64

    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.sageLine.opacity(0.28))
                    .overlay {
                        LinearGradient(colors: [.clear, Color.sageLine.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .offset(x: sweep ? 320 : -320)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frame(height: height)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) { sweep = true }
        }
        .accessibilityLabel("Loading")
    }
}

/// The one notice for dadi being out of reach while Home stays on screen: a
/// glass pill saying what is shown is what dadi last reported, and when.
struct OfflinePill: View {
    /// When dadi stopped answering.
    let since: Date

    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .strokeBorder(Color.inkFaint, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 3]))
                    .frame(width: 15, height: 15)
                    .rotationEffect(.degrees(turning ? 360 : 0))
                Circle()
                    .strokeBorder(Color.inkFaint, style: StrokeStyle(lineWidth: 1.2, dash: [1.5, 1.5]))
                    .frame(width: 5, height: 5)
            }
            Text("dadi is offline").font(.footnote.weight(.semibold)).foregroundStyle(.ink)
            TimelineView(.periodic(from: since, by: 30)) { context in
                Text("\(since, format: .relative(presentation: .named, unitsStyle: .abbreviated)) · reconnecting")
                    .font(.footnote)
                    .foregroundStyle(.inkFaint)
                    .id(context.date)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) { turning = true }
        }
        .accessibilityElement(children: .combine)
    }
}
