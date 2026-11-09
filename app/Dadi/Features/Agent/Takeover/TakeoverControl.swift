import Foundation
import Observation

/// `watching`; `pausing` while Takeover waits for Nas; `inControl`; `returning` while the hand back waits for Nas.
enum ControlState: Equatable, Sendable {
    case watching
    case pausing
    case inControl
    case returning
}

/// How long Ankur may go without input before control is handed back for him. Nas resumes a paused task, with
/// no summary, after 30 minutes without input, so this is shorter and the helper hears what he did first.
let idleReturn: Duration = .seconds(29 * 60)

/// Who controls a helper task in its sheet. The sheet opens watching: input does nothing and the helper keeps
/// working. Takeover pauses the task and lets input through; Return, closing the sheet, or 29 minutes without
/// input hands it back with a summary of what Ankur did.
@MainActor @Observable
final class TakeoverControl {
    private(set) var state = ControlState.watching
    /// A takeover, hand back or input that failed, in words for the sheet; cleared by the next successful step.
    private(set) var problem: String?

    @ObservationIgnored private let isBrowser: Bool
    @ObservationIgnored private var browser = BrowserActivityLog()
    @ObservationIgnored private var terminal = TerminalActivityLog()
    @ObservationIgnored private let pause: () async throws -> Void
    @ObservationIgnored private let resume: (String) async throws -> Void
    @ObservationIgnored private let idle: Duration
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var disposed = false

    /// - Parameters:
    ///   - isBrowser: Whether the summary is a browser's (counts) or a terminal's (commands).
    ///   - idle: How long without input before it hands back by itself.
    ///   - pause: Pauses the task in Nas.
    ///   - resume: Resumes the task in Nas with the summary as the note.
    init(isBrowser: Bool, idle: Duration = idleReturn, pause: @escaping () async throws -> Void, resume: @escaping (String) async throws -> Void) {
        self.isBrowser = isBrowser
        self.idle = idle
        self.pause = pause
        self.resume = resume
    }

    /// Pauses the task and starts a fresh record; a failure leaves it watching. Does nothing unless watching.
    func takeOver() async {
        guard state == .watching, !disposed else { return }
        state = .pausing
        do {
            try await pause()
        } catch {
            state = .watching
            fail("The task did not pause", error)
            return
        }
        browser.reset()
        terminal.reset()
        problem = nil
        state = .inControl
        startTimer()
    }

    /// Resumes the task with the summary and answers true once he is not in control; a failure is reported,
    /// leaves him in control and answers false. Does nothing unless in control.
    func handBack() async -> Bool {
        guard state == .inControl, !disposed else { return state == .watching || disposed }
        stopTimer()
        state = .returning
        do {
            try await resume(isBrowser ? browser.summary() : terminal.summary())
        } catch {
            state = .inControl
            startTimer()
            fail("The task did not resume", error)
            return false
        }
        problem = nil
        state = .watching
        return true
    }

    /// Records what he did in a browser and returns true while he is in control; while he is not, the input is
    /// dropped and this returns false.
    func record(_ event: BrowserActivity) -> Bool {
        guard state == .inControl else { return false }
        browser.record(event)
        startTimer()
        return true
    }

    /// Records what he did in a terminal and returns true while he is in control; while he is not, the input is
    /// dropped and this returns false.
    func record(_ event: TerminalActivity) -> Bool {
        guard state == .inControl else { return false }
        terminal.record(event)
        startTimer()
        return true
    }

    /// Reports a failure of something he did, `what` followed by the error's own words.
    func fail(_ what: String, _ error: any Error) {
        problem = "\(what): \(error.localizedDescription)"
    }

    /// Stops the idle timer and stops handing back: for a sheet that is going away, or a task that was stopped.
    func dispose() {
        disposed = true
        stopTimer()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func startTimer() {
        stopTimer()
        timer = Task { [weak self, idle] in
            do { try await Task.sleep(for: idle) } catch { return }
            guard let self else { return }
            timer = nil
            _ = await handBack()
        }
    }
}
