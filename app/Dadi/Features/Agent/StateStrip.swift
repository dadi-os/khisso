import SwiftUI

/// One chip of the state strip.
struct StripChip: Equatable, Identifiable {
    enum Tone: Equatable {
        case sage, tide, due
    }

    let tone: Tone
    let text: String

    var id: String { text }
}

/// What is true of an agent now, in words: a chip per lane running, what its work lane waits on and unread
/// messages, and the job it was given.
enum AgentState {
    /// One chip per thing true of the agent now. `lanes` are the lanes running now.
    static func chips(_ agent: AgentRecord, lanes: Set<Lane>, unread: Int) -> [StripChip] {
        [
            lanes.contains(.work) ? StripChip(tone: .sage, text: "Working") : nil,
            lanes.contains(.process) ? StripChip(tone: .tide, text: "Processing") : nil,
            agent.running.waitingOn.map { StripChip(tone: .tide, text: "Waiting on \($0.targets.joined(separator: ", "))") },
            unread > 0 ? StripChip(tone: .due, text: "\(unread) unread") : nil,
        ]
        .compactMap { $0 }
    }

    /// Who asked and when, with the request; nil when no job is open.
    static func job(_ status: AgentRecord.Running.Status, nameOf: (String) -> String, timeZone: TimeZone = .current) -> String? {
        status.job.map { "\($0.from.map(nameOf) ?? "Ankur") asked at \(clock($0.at, timeZone: timeZone)): \($0.content)" }
    }

    /// The agent's state in one line: its lanes (or idle, or waiting), its helper tasks and when it last changed.
    static func summary(_ agent: AgentRecord, lanes: Set<Lane>, tasks: Int) -> String {
        let state: String
        if !agent.active {
            state = "Retired"
        } else if !lanes.isEmpty {
            state = [Lane.work, .process].filter(lanes.contains).map { $0 == .work ? "Working" : "Processing" }.joined(separator: " + ")
        } else {
            state = agent.running.waitingOn == nil ? "Idle" : "Waiting on a task"
        }
        return [
            state,
            tasks > 0 ? "\(tasks) helper \(tasks == 1 ? "task" : "tasks")" : nil,
            agent.updatedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    /// The time of day of an ISO 8601 string, as "h:mm a". Hath writes these without fractions,
    /// which the shared date decoder does not read; a string that is no date is shown as sent.
    static func clock(_ iso: String, timeZone: TimeZone = .current) -> String {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = plain.date(from: iso) ?? fractional.date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

/// The chips for what is true of the agent now and the job it was given.
struct StateStrip: View {
    let agent: AgentRecord
    /// The lanes running now.
    let lanes: Set<Lane>
    /// Messages from the agent Ankur has not read.
    let unread: Int
    let nameOf: (String) -> String

    var body: some View {
        let chips = AgentState.chips(agent, lanes: lanes, unread: unread)
        let job = agent.running.status.flatMap { AgentState.job($0, nameOf: nameOf) }
        if !chips.isEmpty || job != nil {
            VStack(alignment: .leading, spacing: 10) {
                if !chips.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(chips) { chip in
                            Text(chip.text)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ink(chip.tone))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(fill(chip.tone), in: .capsule)
                        }
                    }
                }
                if let job {
                    Label {
                        Text(job).font(.footnote).foregroundStyle(.inkMuted).lineLimit(2)
                    } icon: {
                        Image(systemName: "person").font(.footnote).foregroundStyle(.inkMuted)
                    }
                }
            }
        }
    }

    private func ink(_ tone: StripChip.Tone) -> Color {
        switch tone {
        case .sage: .sageText
        case .tide: .tideText
        case .due: .clay
        }
    }

    private func fill(_ tone: StripChip.Tone) -> Color {
        switch tone {
        case .sage: .sage.opacity(0.26)
        case .tide: .tide.opacity(0.2)
        case .due: .clay.opacity(0.16)
        }
    }
}
