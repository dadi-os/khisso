import SwiftUI

/// A task ticked or taken back, shown at once and saved after, then put back with Yaad's reason if it is not saved.
/// A tick offers Undo for a few seconds, and the row waits `PlannerMotion.exitDelay` before it changes group.
@MainActor
@Observable
final class TaskTicker {
    /// Saves a task's done flag.
    typealias Write = @Sendable (_ id: String, _ done: Bool) async throws -> Void

    /// One tick: what Ankur set, whether Yaad has saved it, and whether the row has left for its new group.
    struct Mark: Equatable {
        var done: Bool
        var confirmed = false
        var placed = false
    }

    /// A tick Yaad did not save.
    struct Failure: Equatable {
        let id: String
        let title: String
        let done: Bool
        let message: String
    }

    /// The last tick, offered back for a few seconds.
    struct Undo: Equatable {
        let id: String
        let title: String
        let at = UUID()
    }

    /// How long a tick's Undo stays up.
    static let undoFor: Duration = .seconds(4)

    private let write: Write
    private(set) var marks: [String: Mark] = [:]
    private(set) var failure: Failure?
    private(set) var undo: Undo?
    /// Bumped on each tick, for its haptic.
    private(set) var ticks = 0

    init(write: @escaping Write) {
        self.write = write
    }

    /// `tasks` with Ankur's ticks over them.
    func shown(_ tasks: [PlanTask]) -> [PlanTask] {
        tasks.map { task in marks[task.id].map { task.marked(done: $0.done) } ?? task }
    }

    /// `tasks` as the groups should place them: a ticked task stays where it was until its row has left.
    func placed(_ tasks: [PlanTask]) -> [PlanTask] {
        tasks.map { task in marks[task.id].map { task.marked(done: $0.placed ? $0.done : !$0.done) } ?? task }
    }

    /// Whether `task` reads done, with Ankur's unsaved tick over it.
    func isDone(_ task: PlanTask) -> Bool {
        marks[task.id]?.done ?? task.done
    }

    /// Sets the task done or not on screen at once, then saves it. The returned task finishes when the save does.
    @discardableResult
    func tick(id: String, title: String, done: Bool) -> Task<Void, Never> {
        withAnimation(PlannerMotion.draw) {
            marks[id] = Mark(done: done)
            failure = nil
            ticks += 1
            undo = done ? Undo(id: id, title: title) : nil
        }
        if let shown = undo {
            Task {
                do { try await Task.sleep(for: Self.undoFor) } catch { return }
                if undo == shown { withAnimation(Motion.settle) { undo = nil } }
            }
        }
        Task {
            do { try await Task.sleep(for: PlannerMotion.exitDelay) } catch { return }
            guard marks[id]?.done == done else { return }
            withAnimation(PlannerMotion.exit) { marks[id]?.placed = true }
        }
        return Task {
            do {
                try await write(id, done)
                if marks[id]?.done == done { marks[id]?.confirmed = true }
            } catch {
                guard marks[id]?.done == done else { return }
                withAnimation(Motion.settle) {
                    marks[id] = nil
                    undo = nil
                    failure = Failure(id: id, title: title, done: done, message: error.localizedDescription)
                }
            }
        }
    }

    /// Takes the last tick back.
    func undoLast() {
        guard let undo else { return }
        tick(id: undo.id, title: undo.title, done: false)
    }

    func clearFailure() {
        failure = nil
    }

    /// Drops the ticks Yaad has saved and the rows have followed, once a reload carries them.
    func settle() {
        marks = marks.filter { !($0.value.confirmed && $0.value.placed) }
    }
}
