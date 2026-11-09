import SwiftUI

/// The current time on today's axis, as thaali draws it: a 2 pt sage line from the hour labels to
/// the right edge at the current minute, a 10 pt dot on its start, and a solid chip with the time
/// 8 pt in from the right. It sits above the due lane and takes no touches.
struct NowLine: View {
    /// The minute after midnight at the top of the axis.
    let origin: Int
    /// Points per minute.
    let scale: CGFloat
    /// The whole hours the axis spans.
    let hours: Range<Int>

    private static let chipHeight: CGFloat = 20

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let minute = PlannerLayout.minute(of: context.date)
            if hours.contains(minute / 60) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.sageDeep).frame(height: 2)
                    Circle().fill(Color.sageDeep).frame(width: 10, height: 10).offset(x: -2)
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.bone)
                        .padding(.horizontal, 8)
                        .frame(height: Self.chipHeight)
                        .background(Color.sageDeep, in: .capsule)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                }
                .padding(.leading, 50)
                .offset(y: CGFloat(minute - origin) * scale + 1 - Self.chipHeight / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}
