import SwiftUI

/// One segment of a rail: a title (and symbol) at the rail's type and height; chosen it lifts onto a raised fill.
private struct RailSegment: View {
    let title: String
    var symbol: String?
    var chosen = false
    var emphasis = false
    let run: () -> Void

    var body: some View {
        Button(action: run) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .medium)) }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(chosen ? Color.ink : emphasis ? Color.sageDeep : .inkMuted)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(chosen ? Color.boneRaised : .clear, in: .rect(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(chosen ? 0.08 : 0), radius: 2, y: 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .animation(Motion.snap, value: chosen)
    }
}

/// The rail every sheet's controls sit in: one recessed track of segments sharing a height, radius and type.
private struct RailTrack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 2, content: content)
            .padding(2)
            .background(Color.sage.opacity(0.12), in: .rect(cornerRadius: 11, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.sageLine, lineWidth: 1) }
    }
}

/// A two-option control for a question with a yes and a no ("Going | Not going"): neither is selected until
/// answered, and tapping the chosen one clears it.
struct ChoiceControl: View {
    let first: String
    let second: String
    /// true selects `first`, false `second`, nil neither.
    let selection: Bool?
    /// Called with the new selection: the tapped value, or nil when the chosen one was tapped again.
    let choose: (Bool?) -> Void

    var body: some View {
        RailTrack {
            RailSegment(title: first, chosen: selection == true) { choose(selection == true ? nil : true) }
            RailSegment(title: second, chosen: selection == false) { choose(selection == false ? nil : false) }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// What one segment of an `ActionRail` is.
enum RailItem: Identifiable {
    /// A yes/no pair that selects: "Attended | Didn't attend", where tapping the chosen one clears it.
    case choice(first: String, second: String, selection: Bool?, choose: (Bool?) -> Void)
    /// A plain action: "Message agent", "Mark done".
    case action(title: String, symbol: String?, emphasis: Bool = false, run: () -> Void)

    var id: String {
        switch self {
        case .choice(let first, _, _, _): "choice:\(first)"
        case .action(let title, _, _, _): "action:\(title)"
        }
    }
}

/// A sheet's actions in ONE rail styled like the segmented control: the answer to a question (Attended | Didn't
/// attend) and the plain actions (Message agent, Mark done) as segments of the same track, with the same height,
/// radius and type. When they do not fit one line the rail wraps: each item keeps its own track on its own line.
struct ActionRail: View {
    let items: [RailItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            RailTrack { ForEach(items) { segments($0) } }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    RailTrack { segments(item) }.fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func segments(_ item: RailItem) -> some View {
        switch item {
        case .choice(let first, let second, let selection, let choose):
            RailSegment(title: first, chosen: selection == true) { choose(selection == true ? nil : true) }
            RailSegment(title: second, chosen: selection == false) { choose(selection == false ? nil : false) }
        case .action(let title, let symbol, let emphasis, let run):
            RailSegment(title: title, symbol: symbol, emphasis: emphasis, run: run)
        }
    }
}
