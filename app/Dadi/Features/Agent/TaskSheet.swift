import SwiftUI

/// The modal card for a helper task, watch only: its browser live in a window frame showing the active tab's
/// address, or its terminal's output following the end. The header carries the task's kind, purpose, state and
/// a menu to pause or resume it and to stop it for good. The card is as tall as its browser needs; a terminal
/// opens medium and pulls up to full height.
struct TaskSheet: View {
    let hath: HathClient
    let nas: NasClient
    /// The owning agent's name.
    let owner: String
    /// Reads the tasks again after the task was paused, resumed or stopped.
    let changed: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var task: NasTask
    @State private var actionProblem: String?
    @State private var readProblem: String?
    @State private var busy = false
    @State private var confirmingStop = false
    @State private var fitted: CGFloat = 360

    private static let refresh: Duration = .seconds(2)
    private static let terminalLines = 400
    private static let terminalHeight: CGFloat = 420

    init(hath: HathClient, nas: NasClient, task: NasTask, owner: String, changed: @escaping () async -> Void) {
        self.hath = hath
        self.nas = nas
        self.owner = owner
        self.changed = changed
        _task = State(initialValue: task)
    }

    private var terminal: Bool { task.kind == "terminal" && task.resource != nil }
    private var problem: String? { actionProblem ?? readProblem }

    var body: some View {
        VStack(spacing: 12) {
            header
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            screen
        }
        .padding(.top, 14)
        .padding(.bottom, terminal ? 0 : 16)
        .frame(maxHeight: terminal ? .infinity : nil, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if !terminal { fitted = $0 } }
        .presentationDetents(terminal ? [.height(Self.terminalHeight), .large] : [.height(fitted)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.boneRaised)
        .task { await follow() }
        .confirmationDialog("Stop this task?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop task", role: .destructive) { stop() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Ends the task for good; its agent is told.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.kind == "browser" ? "globe" : "terminal")
                .font(.body.weight(.medium))
                .foregroundStyle(.sageText)
                .frame(width: 32, height: 32)
                .background(.sage.opacity(0.12), in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.purpose).font(.subheadline.weight(.semibold)).foregroundStyle(.ink).lineLimit(2).multilineTextAlignment(.leading)
                Text("\(task.route) \u{00B7} \(owner)").font(.caption.monospaced()).foregroundStyle(.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            TaskStateCapsule(status: task.status)
            if task.stoppable { menu }
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.inkMuted)
                .frame(width: 32, height: 32)
                .background(.ink.opacity(0.06), in: .circle)
        }
        .padding(.horizontal, 16)
    }

    private var menu: some View {
        Menu {
            if task.status == "paused" {
                Button("Resume", systemImage: "play.fill") { change { try await nas.resume(task, note: nil) } }
            } else {
                Button("Pause", systemImage: "pause.fill") { change { try await nas.pause(task) } }
            }
            Button("Stop task", systemImage: "power", role: .destructive) { confirmingStop = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.inkMuted)
                .frame(width: 32, height: 32)
                .background(.ink.opacity(0.06), in: .circle)
        }
        .disabled(busy)
        .accessibilityLabel("More")
    }

    @ViewBuilder
    private var screen: some View {
        if task.kind == "browser", let resource = task.resource, let browserId = Int(resource) {
            BrowserWindow(nas: nas, browserId: browserId, address: task.activeUrl)
                .padding(.horizontal, 16)
        } else if let resource = task.resource {
            GeometryReader { pane in
                ScrollView {
                    TaskTerminal(nas: nas, terminalId: resource, lines: Self.terminalLines, fontSize: 12)
                        .frame(minHeight: pane.size.height, alignment: .top)
                }
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
            }
            .padding(.horizontal, 16)
            .accessibilityLabel("Terminal output")
        } else {
            Text(task.state).font(.footnote).foregroundStyle(.inkMuted).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
        }
    }

    /// Reads the task again every `refresh`, so its state and the page in front stay current.
    private func follow() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.refresh)
                guard let fresh = try await nas.tasks().first(where: { $0.id == task.id }) else {
                    readProblem = "The task is no longer on the box."
                    continue
                }
                task = fresh
                readProblem = nil
            } catch is CancellationError {
                return
            } catch {
                readProblem = "The task could not be read: \(error.localizedDescription)"
            }
        }
    }

    /// Runs a pause or resume, shows the task as Nas answers, and reads the tasks again.
    private func change(_ action: @escaping () async throws -> NasTask) {
        busy = true
        Task {
            defer { busy = false }
            do {
                task = try await action()
                actionProblem = nil
                await changed()
            } catch {
                actionProblem = "The task did not change: \(error.localizedDescription)"
            }
        }
    }

    /// Halts the task through Hath, which kills it and tells its agent, then closes the card.
    private func stop() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await hath.haltSession(agentId: task.owner, taskId: task.id)
                await changed()
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                actionProblem = "The task did not stop: \(WakeFormat.haltSentence(error))"
            }
        }
    }
}

extension View {
    /// Presents the task card for `task` over this view.
    func taskSheet(isPresented: Binding<Bool>, hath: HathClient, nas: NasClient, task: NasTask, owner: String, changed: @escaping () async -> Void) -> some View {
        sheet(isPresented: isPresented) {
            TaskSheet(hath: hath, nas: nas, task: task, owner: owner, changed: changed)
        }
    }
}
