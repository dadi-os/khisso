import SwiftUI

/// A wake's outcome as a chip: running pulses in sage, waiting in tide, yielded stays quiet and dashed,
/// and failed takes the danger tone.
struct OutcomeChip: View {
    let outcome: WakeOutcome

    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            if outcome == .running || outcome == .waiting {
                Circle()
                    .fill(outcome == .running ? Color.sage : .tide)
                    .frame(width: 6, height: 6)
                    .opacity(pulsing ? 0.35 : 1)
            }
            Text(WakeFormat.label(outcome)).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(fill, in: .capsule)
        .overlay { Capsule().strokeBorder(Color.sageLine, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).opacity(outcome == .yielded ? 1 : 0) }
        .onAppear {
            guard !reduceMotion, outcome == .running || outcome == .waiting else { return }
            withAnimation(Motion.breath) { pulsing = true }
        }
        .accessibilityElement(children: .combine)
    }

    private var ink: Color {
        switch outcome {
        case .running: .sageText
        case .waiting: .tideText
        case .yielded: .inkMuted
        case .failed: .danger
        }
    }

    private var fill: Color {
        switch outcome {
        case .running: .sage.opacity(0.26)
        case .waiting: .tide.opacity(0.2)
        case .yielded: .clear
        case .failed: .danger.opacity(0.12)
        }
    }
}

/// One wake of the timeline: why it began, when and for how long, its outcome (with the error of a failed
/// one), what it did and what it cost. Opened, it lists its entries under a lane filter.
struct WakeRow: View {
    let hath: HathClient
    let wake: WakeSummary
    /// Whether the wake shows its entries.
    let open: Bool
    /// The wake's entries once read; nil until then.
    let detail: WakeDetail?
    /// Why the wake could not be read, when it could not.
    let detailError: String?
    let nameOf: (String) -> String
    /// The time the row's durations are measured to while the wake runs.
    let now: Date
    let toggle: () -> Void
    /// Opens the sheet of an agent a name in the wake points to.
    let selectAgent: (String) -> Void
    /// Reads the wake's entries again.
    let retry: () -> Void

    @State private var filter = LaneFilter.all

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
                .contentShape(.rect)
                .onTapGesture(perform: toggle)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: open ? "Collapse" : "Expand", toggle)
            if open { entries.transition(.reveal) }
        }
        .reveals(on: open)
        .background(open ? Color.sage.opacity(0.1) : .clear, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay { if wake.outcome == .failed { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.danger.opacity(0.4), lineWidth: 1) } }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.inkMuted).rotationEffect(.degrees(open ? 90 : 0))
                reason
                Spacer(minLength: 4)
                OutcomeChip(outcome: wake.outcome)
            }
            HStack(spacing: 8) {
                Text(wake.startedAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                Text(WakeFormat.duration(wake, now: now))
                let counts = WakeFormat.counts(wake.counts)
                if !counts.isEmpty { Text(counts) }
                if wake.usage.calls > 0 { Text(WakeFormat.usage(wake.usage)).monospacedDigit() }
            }
            .font(.caption)
            .foregroundStyle(.inkMuted)
            .lineLimit(1)
            .padding(.leading, 20)
            if let opener = wake.openedBy {
                Text(opener.content).font(.caption).foregroundStyle(.inkMuted).lineLimit(open ? 3 : 1).multilineTextAlignment(.leading).padding(.leading, 20)
            }
            if let error = wake.error {
                Text(error).font(.caption).foregroundStyle(.danger).multilineTextAlignment(.leading).textSelection(.enabled).padding(.leading, 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// Why the wake began; the agent that opened it is a link to its sheet.
    @ViewBuilder
    private var reason: some View {
        if wake.reason.kind == .message {
            HStack(spacing: 0) {
                Text("Opened by ")
                AgentLink(agentId: wake.reason.ref, name: wake.reason.ref.map(nameOf) ?? "Ankur", select: selectAgent)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.ink)
        } else {
            Text(WakeFormat.reason(wake.reason, nameOf: nameOf)).font(.footnote.weight(.semibold)).foregroundStyle(.ink).lineLimit(2).multilineTextAlignment(.leading)
        }
    }

    /// The entries of an open wake under the lane filter, or why they are not there: loading, failed, or aged out.
    @ViewBuilder
    private var entries: some View {
        if let detailError, detail == nil {
            VStack(alignment: .leading, spacing: 12) {
                Label("Could not read this wake: \(detailError)", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.danger)
                Button("Try again", action: retry).font(.footnote.weight(.semibold)).foregroundStyle(.sageDeep)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        } else {
            Arrive(ready: detail != nil) {
                WakeSkeleton()
            } content: {
                if let detail { loaded(detail) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func loaded(_ detail: WakeDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if wake.activityTrimmed {
                Text("Details expired").font(.footnote).foregroundStyle(.inkMuted)
            } else {
                Picker("Lane", selection: $filter) {
                    ForEach(LaneFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            let shown = filter.apply(to: detail.entries)
            if shown.isEmpty {
                Text(wake.activityTrimmed ? "No messages were kept." : "Nothing recorded yet.").font(.footnote).foregroundStyle(.inkMuted)
            } else {
                WakeEntryList(hath: hath, agentId: wake.agentId, entries: shown, nameOf: nameOf, selectAgent: selectAgent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
