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
    let tasks: [String]
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
            tasks: status.tasks.map { "\($0.id) · \($0.status) · \($0.current)" },
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

/// The status block on the agent sheet: job, work, last calls, tasks and queued messages.
struct AgentStatusBlock: View {
    let view: AgentStatusView

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            group("JOB") {
                Text(view.job ?? "No open job").font(.footnote).foregroundStyle(.ink).lineLimit(3)
            }
            group("WORK") {
                Text(view.work).font(.footnote).foregroundStyle(.ink)
                if let step = view.step {
                    Text(step).font(.system(.caption, design: .monospaced)).foregroundStyle(.inkMuted).lineLimit(1)
                }
            }
            if !view.recent.isEmpty {
                group("LAST CALLS") {
                    ForEach(view.recent) { call in
                        HStack(spacing: 8) {
                            Text(call.text).font(.system(.caption, design: .monospaced)).foregroundStyle(.inkMuted).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(mark(call.mark)).font(.caption2).foregroundStyle(call.mark == .error ? Color.danger : .inkFaint)
                        }
                    }
                }
            }
            group("TASKS") {
                if let unreadable = view.tasksUnreadable {
                    Text(unreadable).font(.footnote).foregroundStyle(.danger)
                } else if view.tasks.isEmpty {
                    Text("None in flight").font(.footnote).foregroundStyle(.inkMuted)
                } else {
                    ForEach(view.tasks, id: \.self) { line in
                        Text(line).font(.system(.caption, design: .monospaced)).foregroundStyle(.inkMuted).lineLimit(1)
                    }
                }
            }
            if !view.pending.isEmpty {
                group("QUEUED TO SEND") {
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

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(.inkFaint)
            content()
        }
    }
}
