import SwiftUI

/// A browser drawn as a window: a bar with three dots and an address pill showing only the active tab's
/// address, then the live page. `compact` is the small pin in a thread; the task card uses the larger one.
struct BrowserWindow: View {
    let nas: NasClient
    let browserId: Int
    /// The active tab's address, as Nas reports it.
    let address: String?
    var compact = false

    private var textSize: CGFloat { compact ? 10 : 12 }
    private var dot: CGFloat { compact ? 5 : 6 }

    var body: some View {
        VStack(spacing: 0) {
            bar
            BrowserView(nas: nas, browserId: browserId, cornerRadius: 0)
        }
        .background(.boneRaised, in: .rect(cornerRadius: 12, style: .continuous))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.sageLine.opacity(0.7), lineWidth: 1) }
    }

    private var bar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.sageLine).frame(width: dot, height: dot) }
            }
            HStack(spacing: 4) {
                Image(systemName: "lock.fill").font(.system(size: textSize - 2))
                Text(PinnedTasks.pageAddress(address)).font(.system(size: textSize)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.inkMuted)
            .padding(.horizontal, 7)
            .frame(height: compact ? 18 : 24)
            .background(.bone, in: .capsule)
        }
        .padding(.horizontal, 8)
        .frame(height: compact ? 26 : 34)
    }
}
