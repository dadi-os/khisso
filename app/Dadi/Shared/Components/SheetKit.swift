import SwiftUI

/// How a `SituationLine` reads: the dot's colour and the phrase's. `late` is for what is past its time or cannot go on.
enum SituationTone: Equatable {
    case live, wait, late, rest

    var dot: Color {
        switch self {
        case .live: .sage
        case .wait: .tide
        case .late: .lateInk
        case .rest: .inkFaint.opacity(0.7)
        }
    }
}

/// The one situation line of a sheet's header: a 7 pt dot (a check when `done`) and one short phrase in 13.5 pt
/// medium type. Plain type, never a pill.
struct SituationLine: View {
    let tone: SituationTone
    let text: String
    /// A check stands in for the dot once the thing is done or attended.
    var done = false

    var body: some View {
        HStack(spacing: 8) {
            if done {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.sageDeep)
            } else {
                Circle().fill(tone.dot).frame(width: 7, height: 7)
            }
            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(tone == .late ? Color.lateInk : .ink)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The head of every sheet: identity over exactly one situation line. The title wraps and never truncates.
struct SheetHeader<Situation: View>: View {
    let title: String
    @ViewBuilder let situation: () -> Situation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(.ink)
                .textSelection(.enabled)
            situation()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// One fact of a sheet: a quiet label at the left and its value at the right on a line 32 pt tall at least, or, when
/// `wrap`, the label (and its hint) over a value of up to two lines (four when `long`).
struct FactRow<Value: View>: View {
    let label: String
    var hint: String?
    var late = false
    var wrap = false
    var long = false
    @ViewBuilder let value: () -> Value

    var body: some View {
        Group {
            if wrap {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(label).foregroundStyle(.inkMuted)
                        if let hint { Text(hint).foregroundStyle(.inkFaint) }
                    }
                    valueView.lineLimit(long ? 4 : 2).font(.system(size: 13.5, weight: .medium))
                }
                .padding(.vertical, 6)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(label).foregroundStyle(.inkMuted)
                    Spacer(minLength: 8)
                    valueView.lineLimit(1).multilineTextAlignment(.trailing).fontWeight(.medium)
                    if let hint { Text(hint).foregroundStyle(.inkFaint).lineLimit(1) }
                }
                .frame(minHeight: 32)
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var valueView: some View {
        value()
            .monospacedDigit()
            .foregroundStyle(late ? Color.lateInk : .ink)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: wrap)
    }
}

extension FactRow where Value == Text {
    /// A fact whose value is plain text.
    init(label: String, value: String, hint: String? = nil, late: Bool = false, wrap: Bool = false, long: Bool = false) {
        self.init(label: label, hint: hint, late: late, wrap: wrap, long: long) { Text(value) }
    }
}

/// An inset section: a 14 pt rounded soft sage card with 16 pt sides, a caps header and its content.
struct InsetCard<Content: View>: View {
    let title: String
    /// How many rows it holds, when that is a fact worth showing.
    var count: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(1.6).foregroundStyle(.inkFaint)
                if let count { Text(count).font(.system(size: 11)).foregroundStyle(.inkFaint) }
            }
            .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sage.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
    }
}
