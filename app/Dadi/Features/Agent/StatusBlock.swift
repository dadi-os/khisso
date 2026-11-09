import SwiftUI

/// The agent's status block as lines of text, as thaali's popover shows it: the answer to
/// "what are you doing?". Hath sends no status when no lane runs and work is not waiting.
struct AgentStatusView: Equatable {
    enum Mark: Equatable {
        case ok, error, running
    }

    struct Call: Equatable, Identifiable {
        let id: Int
        let text: String
        let mark: Mark
    }

    /// Who asked and when, with the clipped request; nil when no job is open.
    let job: String?
    /// Whether work is running, waiting (on what, since when) or idle.
    let work: String
    let step: String?
    let recent: [Call]
    /// Plain words when Nas could not be read for the tasks; nil otherwise.
    let tasksUnreadable: String?
    /// Messages work queued and process has not sent.
    let pending: [String]

    /// Maps Hath's status to its lines. `nameOf` turns an agent id into its name.
    static func make(_ status: AgentRecord.Running.Status, nameOf: (String) -> String, timeZone: TimeZone = .current) -> AgentStatusView {
        func who(_ id: String?) -> String { id.map(nameOf) ?? "Ankur" }
        func time(_ iso: String) -> String { clock(iso, timeZone: timeZone) }
        let work: String
        switch status.work.state {
        case .waiting:
            work = "Waiting on \(status.work.waitingOn.joined(separator: ", "))" + (status.work.since.map { " since \(time($0))" } ?? "")
        case .running:
            work = "Working" + (status.work.since.map { ", last step \(time($0))" } ?? "")
        case .idle:
            work = "Idle"
        }
        return AgentStatusView(
            job: status.job.map { "\(who($0.from)) asked at \(time($0.at)): \($0.content)" },
            work: work,
            step: status.step,
            recent: status.recent.enumerated().map { index, call in
                Call(id: index, text: call.arg.isEmpty ? call.name : "\(call.name) \(call.arg)", mark: call.ok.map { $0 ? .ok : .error } ?? .running)
            },
            tasksUnreadable: status.tasksUnreadable.map { "Helper tasks could not be read: \($0)" },
            pending: status.pending.map { "To \(who($0.to))\($0.expectsReply ? " (expects a reply)" : ""): \($0.preview)" }
        )
    }

    /// "Waiting on task/browser/3 since 10:20", for an agent whose Hath sent no status.
    static func waitingLabel(_ waiting: AgentRecord.Running.Waiting, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return "Waiting on \(waiting.targets.joined(separator: ", ")) since \(formatter.string(from: waiting.since))"
    }

    /// The time of day of an ISO 8601 string, as "HH:mm". Hath writes these without fractions,
    /// which the shared date decoder does not read; a string that is no date is shown as sent.
    static func clock(_ iso: String, timeZone: TimeZone = .current) -> String {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = plain.date(from: iso) ?? fractional.date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

/// The status block on the agent sheet: a Right now card with the job, the work and its step, then
/// the last calls and the queued messages, each folded until opened.
struct AgentStatusBlock: View {
    let view: AgentStatusView

    @State private var callsOpen = false
    @State private var queuedOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Right now").font(.caption.weight(.semibold)).foregroundStyle(.inkMuted)
                Text(view.work).font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                if let step = view.step {
                    Text(step).font(.system(.caption, design: .monospaced)).foregroundStyle(.inkMuted).lineLimit(1)
                }
                Text(view.job ?? "No open job").font(.footnote).foregroundStyle(.inkMuted).lineLimit(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ink.opacity(0.04), in: .rect(cornerRadius: 16, style: .continuous))
            if !view.recent.isEmpty {
                disclosure("Last calls", count: view.recent.count, isOpen: $callsOpen) {
                    ForEach(view.recent) { call in
                        HStack(spacing: 8) {
                            Text(call.text).font(.system(.caption, design: .monospaced)).foregroundStyle(.inkMuted).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(mark(call.mark)).font(.caption2).foregroundStyle(call.mark == .error ? Color.danger : .inkFaint)
                        }
                    }
                }
            }
            if !view.pending.isEmpty {
                disclosure("Queued to send", count: view.pending.count, isOpen: $queuedOpen) {
                    ForEach(view.pending, id: \.self) { line in
                        Text(line).font(.footnote).foregroundStyle(.inkMuted).lineLimit(2)
                    }
                }
            }
        }
    }

    private func mark(_ mark: AgentStatusView.Mark) -> String {
        switch mark {
        case .ok: "ok"
        case .error: "error"
        case .running: "…"
        }
    }

    private func disclosure(_ title: String, count: Int, isOpen: Binding<Bool>, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(Motion.settle) { isOpen.wrappedValue.toggle() } } label: {
                HStack {
                    Text("\(title) · \(count)").font(.footnote.weight(.semibold)).foregroundStyle(.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.inkFaint).rotationEffect(.degrees(isOpen.wrappedValue ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if isOpen.wrappedValue { VStack(alignment: .leading, spacing: 4, content: content) }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ink.opacity(0.04), in: .rect(cornerRadius: 16, style: .continuous))
    }
}
