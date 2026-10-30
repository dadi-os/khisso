import SwiftUI

/// A task's live screen: its browser's video or its terminal's tail while it holds one, its
/// state summary while it sleeps. It holds a capture on the box only while it is on screen.
struct TaskLive: View {
    let nas: NasClient
    let task: NasTask

    var body: some View {
        if task.status != "asleep", let resource = task.resource {
            if task.kind == "browser", let browserId = Int(resource) {
                BrowserView(nas: nas, browserId: browserId)
            } else {
                TerminalCapture(nas: nas, terminalId: resource)
            }
        } else {
            Text(task.state).font(.footnote).foregroundStyle(.inkMuted)
        }
    }
}

/// The tail of a Nas terminal, read again every second while shown.
private struct TerminalCapture: View {
    let nas: NasClient
    let terminalId: String

    /// Lines read from the pane.
    private static let lines = 40
    private static let poll: Duration = .seconds(1)

    @State private var output: String?
    @State private var problem: String?

    var body: some View {
        Group {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.danger)
            } else if let output {
                Text(output)
                    .font(.system(size: 10, design: .monospaced))
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
                    output = try await nas.terminalCapture(terminalId, lines: Self.lines)
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
