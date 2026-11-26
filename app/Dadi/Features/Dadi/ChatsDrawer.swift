import SwiftUI

/// The Chats tab's drawer: Talk to Dadi, then the filters that narrow the chat list (All, Unread, Working, Waiting,
/// Idle), each with how many chats it keeps and the chosen one tinted sage.
struct ChatsDrawer: View {
    let store: HomeStore
    let filter: ChatGroups.Filter
    /// Opens the router composer and closes the drawer.
    let talk: () -> Void
    /// Narrows the list and closes the drawer.
    let choose: (ChatGroups.Filter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            talkToDadi
            VStack(alignment: .leading, spacing: 2) {
                Text("Show")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.inkMuted)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                ForEach(ChatGroups.Filter.allCases) { row($0) }
            }
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
                    .padding(.horizontal, 6)
            }
        }
        .padding(.horizontal, 14)
        .animation(Motion.snap, value: filter)
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func row(_ option: ChatGroups.Filter) -> some View {
        let chosen = filter == option
        return Button { choose(option) } label: {
            HStack(spacing: 12) {
                Text(option.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ink)
                Spacer(minLength: 8)
                Text("\(option.count(in: store.threads) { store.running(of: $0).state })")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.inkMuted)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(chosen ? Color.sage.opacity(0.16) : .clear, in: .rect(cornerRadius: 16, style: .continuous))
            .contentShape(.rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var talkToDadi: some View {
        Button(action: talk) {
            HStack(spacing: 12) {
                ZStack {
                    if store.routing {
                        PulseOut()
                    }
                    Text("દ")
                        .font(.wordmark(21))
                        .foregroundStyle(store.routing ? Color.sageDeep : .sageText)
                        .inkCentered(.letter, size: 21)
                        .frame(width: 34, height: 34)
                        .background(.sage.opacity(store.routing ? 0.26 : 0.14), in: .circle)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Talk to Dadi")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.ink)
                    if store.routing {
                        HStack(spacing: 6) {
                            ProcessingMark()
                            Text("routing").font(.footnote).foregroundStyle(.sageText)
                        }
                        .transition(.opacity)
                    } else {
                        Text("Start something new")
                            .font(.footnote)
                            .foregroundStyle(.inkFaint)
                            .transition(.opacity)
                    }
                }
                Spacer()
            }
            .animation(Motion.settle, value: store.routing)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

/// Thaali's live ring: a sage disc swelling out and fading behind a busy mark.
private struct PulseOut: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(.sage.opacity(0.45))
            .frame(width: 34, height: 34)
            .phaseAnimator([false, true]) { ring, out in
                ring.scaleEffect(out ? 1.55 : 1).opacity(out ? 0 : 0.55)
            } animation: { out in
                out && !reduceMotion ? .easeOut(duration: 2.4) : nil
            }
    }
}
