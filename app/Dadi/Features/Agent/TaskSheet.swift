import SwiftUI

/// The full-height sheet for a helper task's browser or terminal. It opens watching: the helper keeps working
/// and taps and keys do nothing. Takeover pauses the helper and lets Ankur in; Return, closing the sheet or
/// 29 minutes without input hands the task back with a summary of what he did, and the sheet goes on
/// watching. Stop task is in the menu, behind a confirmation.
struct TaskSheet: View {
    let nas: NasClient
    let task: NasTask
    /// The owning agent's name.
    let owner: String
    /// Reads the tasks again after the task was paused, resumed or stopped.
    let changed: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var control: TakeoverControl
    @State private var confirmingStop = false
    @State private var stopping = false

    init(nas: NasClient, task: NasTask, owner: String, changed: @escaping () async -> Void) {
        self.nas = nas
        self.task = task
        self.owner = owner
        self.changed = changed
        _control = State(initialValue: TakeoverControl(
            isBrowser: task.kind == "browser",
            pause: {
                _ = try await nas.pause(task)
                await changed()
            },
            resume: { summary in
                _ = try await nas.resume(task, note: summary)
                await changed()
            }
        ))
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            if let problem = control.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            if task.kind == "browser", let resource = task.resource, let browserId = Int(resource) {
                BrowserDrive(nas: nas, browserId: browserId, control: control)
            } else if let resource = task.resource {
                TerminalPane(nas: nas, terminalId: resource, control: control)
            } else {
                Text(task.state).font(.footnote).foregroundStyle(.inkMuted).padding()
                Spacer()
            }
        }
        .padding(.top, 8)
        .onDisappear {
            let control = control
            Task {
                _ = await control.handBack()
                control.dispose()
            }
        }
        .confirmationDialog("Stop this task?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop task", role: .destructive) { stop() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("It goes to sleep and \(owner) is told it was stopped.")
        }
    }

    private var busy: Bool { control.state == .pausing || control.state == .returning || stopping }

    private var header: some View {
        HStack(spacing: 8) {
            Button("Close") { close() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.sageDeep)
                .frame(minWidth: 56, minHeight: 44, alignment: .leading)
                .disabled(busy)
            VStack(spacing: 0) {
                Text(task.route).font(.subheadline.monospaced().weight(.semibold)).foregroundStyle(.ink).lineLimit(1)
                Text("\(owner) · \(stateWord)").font(.caption).foregroundStyle(.inkMuted).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 4) {
                if task.drivable { handle }
                if task.stoppable {
                    Menu {
                        Button("Stop task", systemImage: "power", role: .destructive) { confirmingStop = true }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.sageDeep).frame(width: 36, height: 44)
                    }
                    .disabled(busy)
                    .accessibilityLabel("More")
                }
            }
            .frame(minWidth: 56, alignment: .trailing)
        }
        .padding(.horizontal, 16)
    }

    /// Takeover while watching, Return while in control.
    private var handle: some View {
        let inControl = control.state == .inControl || control.state == .returning
        return Button(inControl ? "Return" : "Takeover") {
            Task { if inControl { _ = await control.handBack() } else { await control.takeOver() } }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(inControl ? .tide : .sageDeep)
        .foregroundStyle(inControl ? Color.tideText : .white)
        .disabled(busy)
        .accessibilityLabel(inControl ? "Return" : "Takeover")
    }

    private var stateWord: String {
        switch control.state {
        case .watching: "Watching"
        case .pausing: "Pausing\u{2026}"
        case .inControl: "You are in control"
        case .returning: "Returning\u{2026}"
        }
    }

    /// Hands the task back when he is in control, then closes; a failed hand back keeps the sheet open.
    private func close() {
        Task {
            if await control.handBack() { dismiss() }
        }
    }

    /// Pauses the task, stops it, and closes the sheet; a failure is said in the sheet.
    private func stop() {
        stopping = true
        Task {
            defer { stopping = false }
            do {
                _ = try await nas.pause(task)
                _ = try await nas.stop(task)
                control.dispose()
                await changed()
                dismiss()
            } catch {
                control.fail("The task did not stop", error)
            }
        }
    }
}

extension View {
    /// Presents the sheet for `task` over this view.
    func taskSheet(isPresented: Binding<Bool>, nas: NasClient, task: NasTask, owner: String, changed: @escaping () async -> Void) -> some View {
        sheet(isPresented: isPresented) {
            TaskSheet(nas: nas, task: task, owner: owner, changed: changed)
                .presentationDetents([.large])
                .presentationBackground(.boneRaised)
        }
    }
}
