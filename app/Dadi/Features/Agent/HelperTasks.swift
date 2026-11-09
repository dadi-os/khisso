import SwiftUI

/// The agent's helper tasks: a row each (opening it shows its live view) and, while the task can still
/// be stopped, a Stop that asks first. A refused stop is said under its row in plain words and the row
/// stays as it was.
struct HelperTasks: View {
    let hath: HathClient
    let nas: NasClient
    let agentId: String
    /// The owning agent's name.
    let owner: String
    /// The agent's helper tasks, most recently active first.
    let tasks: [NasTask]
    /// The task whose preview is open; only one holds a capture on the box at a time.
    @Binding var opened: String?
    /// Reads the tasks again, after one was stopped or changed.
    let changed: () async -> Void

    @State private var confirming: NasTask?
    @State private var halting: String?
    @State private var refused: [String: String] = [:]

    private var active: Int { tasks.filter(\.stoppable).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HELPER TASKS · \(tasks.count) · \(active) ACTIVE")
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.inkFaint)
            VStack(spacing: 0) {
                ForEach(tasks) { task in
                    TaskRow(nas: nas, task: task, owner: owner, opened: $opened, changed: changed)
                    if task.stoppable { stop(task) }
                    if let reason = refused[task.id] {
                        Label("Could not stop \(task.route): \(reason)", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 10)
                    }
                    if task.id != tasks.last?.id { Rectangle().fill(.rule).frame(height: 1) }
                }
            }
            .padding(.horizontal, 14)
            .background(Color.ink.opacity(0.04), in: .rect(cornerRadius: 16, style: .continuous))
        }
        .confirmationDialog("Stop this task?", isPresented: Binding { confirming != nil } set: { if !$0 { confirming = nil } }, titleVisibility: .visible, presenting: confirming) { task in
            Button("Stop \(task.route)", role: .destructive) { Task { await halt(task) } }
            Button("Keep", role: .cancel) {}
        }
    }

    private func stop(_ task: NasTask) -> some View {
        HStack {
            Spacer()
            Button { confirming = task } label: {
                if halting == task.id { ProgressView().controlSize(.small) } else { Text("Stop") }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.danger)
            .disabled(halting != nil)
            .accessibilityLabel("Stop \(task.route)")
        }
        .padding(.bottom, 8)
    }

    private func halt(_ task: NasTask) async {
        halting = task.id
        defer { halting = nil }
        do {
            try await hath.haltSession(agentId: agentId, taskId: task.id)
            refused[task.id] = nil
        } catch is CancellationError {
            return
        } catch {
            refused[task.id] = WakeFormat.haltSentence(error)
        }
        await changed()
    }
}
