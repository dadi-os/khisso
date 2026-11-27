import SwiftUI

/// The modal card for a helper task, watch only, in the shared sheet anatomy: its purpose over its state, its facts,
/// a rail to pause or resume it and to stop it for good, and under them its browser live in a window frame showing
/// the active tab's address, or its terminal's output following the end. The card is as tall as its browser needs; a terminal
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

    /// The facts a task's sheet lists, in order: whose it is, which task, what it is doing now, the page in front, and
    /// when it last did anything. Only the true ones.
    static func facts(of task: NasTask, owner: String) -> [(label: String, value: String)] {
        var rows = [("Agent", owner), ("Task", task.route)]
        if task.status != "asking", !task.state.isEmpty { rows.append(("Now", task.state)) }
        if let url = task.activeUrl, !url.isEmpty { rows.append(("Page", url)) }
        rows.append(("Last active", task.lastActivity.formatted(.relative(presentation: .numeric, unitsStyle: .wide))))
        return rows
    }

    /// The one situation line: the task's state in words, toned as the rows' state words are.
    static func situation(of task: NasTask, owner: String) -> (tone: SituationTone, text: String) {
        switch task.status {
        case "working": (.live, "Working")
        case "paused": (.wait, "Paused")
        case "asking": (.wait, "Waiting on \(owner)")
        case "stopped": (.late, "Stopped")
        default: (.rest, task.status.capitalized)
        }
    }

    var body: some View {
        let situation = Self.situation(of: task, owner: owner)
        VStack(alignment: .leading, spacing: SheetLayout.gap) {
            SheetHeader(title: task.purpose) { SituationLine(tone: situation.tone, text: situation.text) }
                .padding(.horizontal, SheetLayout.inset)
            VStack(spacing: 0) {
                ForEach(Self.facts(of: task, owner: owner), id: \.label) { row in
                    FactRow(label: row.label, value: row.value, wrap: row.label == "Now" || row.label == "Page", long: row.label == "Now")
                }
            }
            .padding(.horizontal, SheetLayout.inset)
            if task.stoppable {
                Divider().overlay(Color.rule).padding(.horizontal, SheetLayout.inset)
                ActionRail(items: rail)
                    .padding(.horizontal, SheetLayout.inset)
                    .disabled(busy)
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SheetLayout.inset)
            }
            screen
        }
        .padding(.top, SheetLayout.inset)
        .padding(.bottom, terminal ? 0 : SheetLayout.inset)
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

    /// Pause or Resume, and Stop, in the sheet's one rail.
    private var rail: [RailItem] {
        [
            task.status == "paused"
                ? .action(title: "Resume", symbol: "play.fill") { change { try await nas.resume(task, note: nil) } }
                : .action(title: "Pause", symbol: "pause.fill") { change { try await nas.pause(task) } },
            .action(title: "Stop task", symbol: "power") { confirmingStop = true },
        ]
    }

    @ViewBuilder
    private var screen: some View {
        if task.kind == "browser", let resource = task.resource, let browserId = Int(resource) {
            BrowserWindow(nas: nas, browserId: browserId, address: task.activeUrl)
                .padding(.horizontal, SheetLayout.inset)
        } else if let resource = task.resource {
            GeometryReader { pane in
                ScrollView {
                    TaskTerminal(nas: nas, terminalId: resource, lines: Self.terminalLines, fontSize: 12)
                        .frame(minHeight: pane.size.height, alignment: .top)
                }
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
            }
            .padding(.horizontal, SheetLayout.inset)
            .accessibilityLabel("Terminal output")
        } else {
            Text(task.state).font(.footnote).foregroundStyle(.inkMuted).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, SheetLayout.inset)
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
