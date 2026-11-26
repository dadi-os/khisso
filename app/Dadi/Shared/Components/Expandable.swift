import SwiftUI

/// How an `Expandable` sits: a `card` takes a hairline border and a raised fill while open (a wake, a charter, a
/// group of tasks); a `row` is a bare compact line (a tool call, a thought).
enum ExpandableLook {
    case card
    case row
}

/// The one disclosure of the app, thaali's Expandable: a summary row with a chevron that turns a quarter, a title,
/// a quieter secondary line and a trailing value, opening inline to its content. The whole summary is one button
/// that reports its expanded state; the content eases open under it, indented to start beneath the title. A failed
/// card (`late`) keeps the late border. Plain type everywhere, never a pill.
struct Expandable<Title: View, Secondary: View, Trailing: View, Content: View>: View {
    @Binding var isOpen: Bool
    var look: ExpandableLook = .card
    /// A card that needs attention, such as a failed wake, keeps the late border.
    var late = false
    /// An SF Symbol in a slot before the title, as a folder row has.
    var icon: String?
    @ViewBuilder let title: () -> Title
    @ViewBuilder let secondary: () -> Secondary
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var card: Bool { look == .card }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : Motion.snap) { isOpen.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.inkMuted)
                        .frame(width: 12, height: 17)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .animation(reduceMotion ? nil : Motion.snap, value: isOpen)
                    if let icon {
                        Image(systemName: icon).font(.system(size: 13)).foregroundStyle(.sageDeep).frame(width: 18, height: 17)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        title()
                            .font(.system(size: card ? 13.5 : 12.5, weight: card ? .semibold : .regular))
                            .foregroundStyle(.ink)
                            .multilineTextAlignment(.leading)
                        secondary()
                            .font(.system(size: 12))
                            .foregroundStyle(.inkMuted)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    trailing()
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.inkMuted)
                        .padding(.top, 1)
                }
                .padding(.horizontal, card ? 12 : 6)
                .padding(.vertical, card ? 10 : 4)
                .frame(minHeight: card ? 44 : 28)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            if isOpen {
                content()
                    .padding(.leading, card ? 34 : 26)
                    .padding(.trailing, card ? 12 : 0)
                    .padding(.bottom, card ? 12 : 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .background {
            if card { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isOpen ? Color.boneRaised : .clear) }
        }
        .overlay {
            if card {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(late ? Color.lateLine : isOpen ? Color.rule : .clear, lineWidth: 1)
            }
        }
        .clipShape(.rect(cornerRadius: card ? 14 : 8, style: .continuous))
        .animation(reduceMotion ? nil : Motion.settle, value: isOpen)
    }
}

extension Expandable where Secondary == EmptyView, Trailing == EmptyView {
    /// An expandable with a title and content only.
    init(isOpen: Binding<Bool>, look: ExpandableLook = .card, late: Bool = false, icon: String? = nil, @ViewBuilder title: @escaping () -> Title, @ViewBuilder content: @escaping () -> Content) {
        self.init(isOpen: isOpen, look: look, late: late, icon: icon, title: title, secondary: { EmptyView() }, trailing: { EmptyView() }, content: content)
    }
}

extension Expandable where Secondary == EmptyView {
    /// An expandable with a title and a trailing value.
    init(isOpen: Binding<Bool>, look: ExpandableLook = .card, late: Bool = false, icon: String? = nil, @ViewBuilder title: @escaping () -> Title, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.init(isOpen: isOpen, look: look, late: late, icon: icon, title: title, secondary: { EmptyView() }, trailing: trailing, content: content)
    }
}
