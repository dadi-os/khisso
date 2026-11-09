import SwiftUI

/// One helper task as a row, the same on the agent sheet and the System page: its address, purpose
/// and step, a state capsule, and under it the helper's own words when it asked its agent. Tapping
/// the row opens the task sheet, where its browser or terminal is watched and taken over.
struct TaskRow: View {
    let nas: NasClient
    let task: NasTask
    /// The owning agent's name.
    let owner: String
    /// True where the row stands apart from its agent, as on System.
    var showsOwner = false
    /// Reads the tasks again, after Ankur paused, resumed or stopped this one.
    let changed: () async -> Void

    @State private var acting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { acting = true } label: { head }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the task")
            note
        }
        .taskSheet(isPresented: $acting, nas: nas, task: task, owner: owner, changed: changed)
    }

    private var head: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.kind == "browser" ? "globe" : "terminal")
                .font(.body.weight(.medium))
                .foregroundStyle(.sageText)
                .frame(width: 32, height: 32)
                .background(.sage.opacity(0.12), in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(task.route).font(.footnote.monospaced().weight(.medium)).foregroundStyle(.ink).lineLimit(1)
                if showsOwner { Text(owner).font(.caption).foregroundStyle(.inkMuted).lineLimit(1) }
                Text(task.purpose).font(.footnote).foregroundStyle(.ink).lineLimit(2).multilineTextAlignment(.leading)
                if task.status != "asleep", task.status != "asking" {
                    Text(task.state).font(.caption.monospaced()).foregroundStyle(.inkMuted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                TaskStateCapsule(status: task.status)
                Text(task.lastActivity, style: .relative).font(.caption2).foregroundStyle(.inkFaint)
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.inkFaint)
            }
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    /// What a waiting or paused task says under its row.
    @ViewBuilder
    private var note: some View {
        if task.status == "asking" {
            VStack(alignment: .leading, spacing: 3) {
                Text("Asked \(owner)").font(.caption.weight(.semibold)).foregroundStyle(.tideText)
                Text(task.state).font(.footnote).foregroundStyle(.ink).lineLimit(3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tide.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
            .padding(.leading, 44)
            .padding(.bottom, 12)
        } else if task.status == "paused" {
            Label("Paused while you are in it. Return it from its sheet.", systemImage: "pause.fill")
                .font(.footnote)
                .foregroundStyle(.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tide.opacity(0.2), in: .rect(cornerRadius: 12, style: .continuous))
                .padding(.leading, 44)
                .padding(.bottom, 12)
        }
    }
}

/// A task's state word as a capsule: working in sage, paused and waiting in tide (waiting dashed),
/// idle and asleep outlined (asleep dashed).
struct TaskStateCapsule: View {
    let status: String

    var body: some View {
        HStack(spacing: 5) {
            if status == "paused" { Image(systemName: "pause.fill").font(.system(size: 9)) }
            Text(label).font(.caption.weight(.semibold))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(fill, in: .capsule)
        .overlay { Capsule().strokeBorder(line, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : [])) }
    }

    /// An `asking` task is waiting on its agent; the rest say what Nas says.
    private var label: String { status == "asking" ? "waiting" : status }
    private var dashed: Bool { status == "asking" || status == "asleep" }

    private var ink: Color {
        switch status {
        case "working": .sageText
        case "paused", "asking": .tideText
        default: .inkMuted
        }
    }

    private var fill: Color {
        switch status {
        case "working": .sage.opacity(0.26)
        case "paused": .tide.opacity(0.2)
        case "asking": .tide.opacity(0.1)
        default: .clear
        }
    }

    private var line: Color {
        switch status {
        case "asking": .tide.opacity(0.6)
        case "idle", "asleep": .sageLine
        default: .clear
        }
    }
}

/// The tail of a Nas terminal, read again every `poll` while shown and the app is forward.
struct TaskTerminal: View {
    let nas: NasClient
    let terminalId: String
    /// Lines read from the pane.
    let lines: Int
    let fontSize: CGFloat
    var poll: Duration = .seconds(1)

    @State private var output: String?
    @State private var problem: String?
    @Environment(\.scenePhase) private var scenePhase

    private struct ReadKey: Hashable {
        let terminalId: String
        let poll: Duration
        let forward: Bool
    }

    var body: some View {
        Group {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.danger)
            } else if let output {
                Text(output)
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.sage.opacity(0.08), in: .rect(cornerRadius: 12))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: ReadKey(terminalId: terminalId, poll: poll, forward: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do {
                    output = try await nas.terminalCapture(terminalId, lines: lines)
                    problem = nil
                } catch is CancellationError {
                    return
                } catch {
                    problem = error.localizedDescription
                }
                do { try await Task.sleep(for: poll) } catch { return }
            }
        }
    }
}
