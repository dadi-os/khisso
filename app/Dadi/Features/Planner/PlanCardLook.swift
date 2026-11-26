import SwiftUI

/// Where a plan card stands for how it is drawn: what the clock says and what Ankur said.
enum PlanCardState: Equatable {
    case upcoming, current, past, attended, missed, declined

    /// A declined plan is `declined`; Ankur's answer decides next (`attended`, `missed`); otherwise the clock does.
    static func of(_ plan: Plan, state: TimeState) -> PlanCardState {
        if plan.declined { return .declined }
        switch plan.attended {
        case true?: return .attended
        case false?: return .missed
        case nil: break
        }
        switch state {
        case .now: return .current
        case .past: return .past
        case .next, .later: return .upcoming
        }
    }
}

/// How a plan card looks in Day, Week and the widget, so Attended reads at a glance and not as a small check:
/// attended is a solid sage card with a firm 1.5 pt sage border, a check for its dot and an "Attended" caption where
/// there is room; past and unanswered is a quiet card; didn't attend is muted, dashed, with a struck title; declined
/// is muted and dashed without a strike.
struct PlanCardLook: Equatable {
    enum Fill: Equatable { case slab, past, now, attended, none }
    enum Border: Equatable { case line, now, attended, faint }

    let fill: Fill
    let border: Border
    let lineWidth: CGFloat
    let dashed: Bool
    let opacity: Double
    let struck: Bool
    /// What the card says about Ankur's answer where there is room for it.
    let caption: String?
    /// A check stands in for the tone dot.
    let check: Bool

    init(_ state: PlanCardState) {
        switch state {
        case .upcoming: (fill, border, lineWidth, dashed, opacity, struck, caption, check) = (.slab, .line, 1, false, 1, false, nil, false)
        case .current: (fill, border, lineWidth, dashed, opacity, struck, caption, check) = (.now, .now, 1, false, 1, false, nil, false)
        case .past: (fill, border, lineWidth, dashed, opacity, struck, caption, check) = (.past, .line, 1, false, 0.62, false, nil, false)
        case .attended: (fill, border, lineWidth, dashed, opacity, struck, caption, check) = (.attended, .attended, 1.5, false, 1, false, "Attended", true)
        case .missed: (fill, border, lineWidth, dashed, opacity, struck, caption, check) = (.none, .faint, 1, true, 0.6, true, "Didn’t attend", false)
        case .declined: (fill, border, lineWidth, dashed, opacity, struck, caption, check) = (.none, .faint, 1, true, 0.75, false, nil, false)
        }
    }

    init(_ plan: Plan, state: TimeState) {
        self.init(PlanCardState.of(plan, state: state))
    }

    /// A widget row that is neither current, answered nor declined: no card at all, muted once ended.
    static func row(ended: Bool) -> PlanCardLook {
        PlanCardLook(fill: .none, border: .line, lineWidth: 0, dashed: false, opacity: ended ? 0.55 : 1, struck: false, caption: nil, check: false)
    }

    private init(fill: Fill, border: Border, lineWidth: CGFloat, dashed: Bool, opacity: Double, struck: Bool, caption: String?, check: Bool) {
        (self.fill, self.border, self.lineWidth, self.dashed, self.opacity, self.struck, self.caption, self.check) = (fill, border, lineWidth, dashed, opacity, struck, caption, check)
    }

    var fillColor: Color {
        switch fill {
        case .slab: .slab
        case .past: .slabPast
        case .now: .slabNowFill
        case .attended: .slabAttended
        case .none: .clear
        }
    }

    var borderColor: Color {
        switch border {
        case .line: .slabLine
        case .now: .slabNow
        case .attended: .slabAttendedLine
        case .faint: .slabDeclined
        }
    }
}

extension View {
    /// Draws `look` as this view's card: an opaque bone base, its fill, its border and its opacity.
    func planCardSurface(_ look: PlanCardLook, radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            shape.fill(Color.bone)
            shape.fill(look.fillColor)
        }
        .overlay { shape.strokeBorder(look.borderColor, style: StrokeStyle(lineWidth: look.lineWidth, dash: look.dashed ? [4, 3] : [])) }
        .opacity(look.opacity)
    }
}
