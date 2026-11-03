import SwiftUI

/// One helper task as a row, the same on the agent sheet and the System page: its address, purpose
/// and step, a state capsule, and under it the helper's own words when it asked its agent. Opening
/// the row shows its browser or terminal; tapping that preview opens the task sheet to act in it.
struct TaskRow: View {
    let nas: NasClient
    let task: NasTask
    /// The owning agent's name.
    let owner: String
    /// True where the row stands apart from its agent, as on System.
    var showsOwner = false
    /// The task whose preview is open; only one holds a capture on the box at a time.
    @Binding var opened: String?
    /// Reads the tasks again, after Ankur paused, resumed or stopped this one.
    let changed: () async -> Void

    @State private var acting = false

    private var open: Bool { opened == task.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(Motion.settle) { opened = open ? nil : task.id } } label: { head }
                .buttonStyle(.plain)
                .accessibilityHint(open ? "Closes the preview" : "Opens the preview")
            note
            if open {
                Group {
                    if task.drivable {
                        TaskPreview(nas: nas, task: task) { acting = true }
                    } else {
                        Text(task.state).font(.footnote).foregroundStyle(.inkMuted)
                    }
                }
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $acting) {
            TaskSheet(nas: nas, task: task, owner: owner, changed: changed)
                .presentationDetents([.large])
                .presentationBackground(.boneRaised)
        }
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
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.inkFaint).rotationEffect(.degrees(open ? 90 : 0))
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
            Label("Paused while you are in it. Closing its sheet asks what happens next.", systemImage: "pause.fill")
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

/// A task's browser or terminal as a preview that opens the task sheet when tapped: no badge and no
/// button, the preview is the button.
struct TaskPreview: View {
    let nas: NasClient
    let task: NasTask
    let expand: () -> Void

    var body: some View {
        Button(action: expand) {
            ZStack(alignment: .topTrailing) {
                if task.kind == "browser", let resource = task.resource, let browserId = Int(resource) {
                    BrowserView(nas: nas, browserId: browserId)
                } else if let resource = task.resource {
                    TaskTerminal(nas: nas, terminalId: resource, lines: 40, fontSize: 10)
                }
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.inkMuted)
                    .frame(width: 26, height: 26)
                    .background(.thinMaterial, in: .circle)
                    .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                if task.status == "paused" {
                    Label("Paused", systemImage: "pause.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tideText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(.thinMaterial, in: .capsule)
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.kind == "browser" ? "Open the browser" : "Open the terminal")
    }
}

/// The tail of a Nas terminal, read again every second while shown.
struct TaskTerminal: View {
    let nas: NasClient
    let terminalId: String
    /// Lines read from the pane.
    let lines: Int
    let fontSize: CGFloat

    private static let poll: Duration = .seconds(1)

    @State private var output: String?
    @State private var problem: String?

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
        .task(id: terminalId) {
            while !Task.isCancelled {
                do {
                    output = try await nas.terminalCapture(terminalId, lines: lines)
                    problem = nil
                } catch is CancellationError {
                    return
                } catch {
                    problem = error.localizedDescription
                }
                do { try await Task.sleep(for: Self.poll) } catch { return }
            }
        }
    }
}
