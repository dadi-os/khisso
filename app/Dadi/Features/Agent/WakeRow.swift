import SwiftUI

/// A wake's outcome as plain type with a dot: running pulses in sage, waiting is tide, yielded stays quiet and
/// failed takes the late tone.
struct OutcomeWord: View {
    let outcome: WakeOutcome

    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 6, height: 6).opacity(outcome == .running && pulsing ? 0.35 : 1)
            Text(WakeFormat.label(outcome)).fontWeight(.medium)
        }
        .foregroundStyle(outcome == .failed ? Color.lateInk : .inkMuted)
        .onAppear {
            guard !reduceMotion, outcome == .running else { return }
            withAnimation(Motion.breath) { pulsing = true }
        }
        .accessibilityElement(children: .combine)
    }

    private var dot: Color {
        switch outcome {
        case .running: .sage
        case .waiting: .tide
        case .yielded: .inkFaint.opacity(0.7)
        case .failed: .lateInk
        }
    }
}

/// One wake of the timeline in the shared Expandable: why it began and how it ended on the first line, when and for
/// how long and what it did on the second. Opened, it lists its entries.
struct WakeRow: View {
    let hath: HathClient
    let wake: WakeSummary
    /// Whether the wake shows its entries.
    let open: Bool
    /// The wake's entries once read; nil until then.
    let detail: WakeDetail?
    /// Why the wake could not be read, when it could not.
    let detailError: String?
    /// The agent's routines and reminders, to name the wake one fired.
    let routines: Routines?
    let nameOf: (String) -> String
    /// The time the row's durations are measured to while the wake runs.
    let now: Date
    let toggle: () -> Void
    /// Opens the sheet of an agent a name in the wake points to.
    let selectAgent: (String) -> Void
    /// Reads the wake's entries again.
    let retry: () -> Void

    var body: some View {
        Expandable(isOpen: Binding { open } set: { _ in toggle() }, late: wake.outcome == .failed) {
            Text(WakeFormat.reasonText(wake.reason, routines: routines, nameOf: nameOf))
        } secondary: {
            VStack(alignment: .leading, spacing: 2) {
                Text(WakeFormat.facts(wake, now: now))
                if let error = wake.error {
                    Text(error).font(.system(size: 12.5)).foregroundStyle(.lateInk).textSelection(.enabled)
                }
            }
        } trailing: {
            OutcomeWord(outcome: wake.outcome)
        } content: {
            entries
        }
    }

    /// The entries of an open wake, or why they are not there: loading, failed, or aged out.
    @ViewBuilder
    private var entries: some View {
        if let detailError, detail == nil {
            VStack(alignment: .leading, spacing: 12) {
                Label("Could not read this wake: \(detailError)", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.danger)
                Button("Try again", action: retry).font(.footnote.weight(.semibold)).foregroundStyle(.sageDeep)
            }
        } else {
            Arrive(ready: detail != nil) {
                WakeSkeleton()
            } content: {
                if let detail { loaded(detail) }
            }
        }
    }

    private func loaded(_ detail: WakeDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if wake.activityTrimmed {
                Text("Details expired").font(.footnote).foregroundStyle(.inkMuted)
            }
            if detail.entries.isEmpty {
                Text(wake.activityTrimmed ? "No messages were kept." : "Nothing recorded yet.").font(.footnote).foregroundStyle(.inkMuted)
            } else {
                WakeEntryList(hath: hath, agentId: wake.agentId, entries: detail.entries, nameOf: nameOf, selectAgent: selectAgent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
