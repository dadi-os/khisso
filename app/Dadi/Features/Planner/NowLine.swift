import SwiftUI

/// The current time on today's axis, as thaali draws it: a 2 pt sage-deep line across the day, and a 20 pt-tall
/// rounded pill with the time (bone text, 11 bold) centred on it in the axis column. No dot, and it takes no touches.
struct NowLine: View {
    /// The minute after midnight at the top of the axis.
    let origin: Int
    /// Points per minute.
    let scale: CGFloat
    /// The width of the hour-label column the pill sits in.
    let axisWidth: CGFloat
    /// The minutes the axis spans, from `origin`.
    let span: Int
    /// Draws the time without its AM or PM, for a narrow axis.
    var short = false
    /// Space above the axis's first minute.
    var inset: CGFloat = 0
    /// How visible the line is; the pill stays solid.
    var lineOpacity = 1.0

    private static let pillHeight: CGFloat = 20

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let minute = PlannerLayout.minute(of: context.date)
            if minute >= origin && minute <= origin + span {
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.sageDeep).frame(height: 2).padding(.leading, axisWidth - 4).opacity(lineOpacity)
                    Text(short ? context.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()) : context.date.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.bone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: axisWidth - 10, height: Self.pillHeight)
                        .background(Color.sageDeep, in: .capsule)
                        .offset(x: 2, y: -(Self.pillHeight / 2 - 1))
                }
                .offset(y: inset + CGFloat(minute - origin) * scale)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}
