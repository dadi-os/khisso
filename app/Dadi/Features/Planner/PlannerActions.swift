import SwiftUI
import UIKit

/// Timings the Planner shares with thaali's: a check draws in 0.32 s, and a ticked row waits 0.38 s before it
/// leaves for Done over 0.32 s. Snap (0.32 s), settle (0.55 s) and the fast 0.18 s are the app's `Motion`.
enum PlannerMotion {
    static let draw = Animation.easeOut(duration: 0.32)
    static let fast = Animation.easeOut(duration: 0.18)
    static let exit = Animation.smooth(duration: 0.32)
    static let exitDelay: Duration = .milliseconds(380)
}

/// What a Planner sheet is about.
enum PlannerSheet: Identifiable, Equatable {
    case plan(Plan)
    case task(PlanTask)
    case day(Date)
    case someday

    var id: String {
        switch self {
        case .plan(let plan): "plan:\(plan.id)"
        case .task(let task): "task:\(task.id)"
        case .day(let day): "day:\(day.timeIntervalSince1970)"
        case .someday: "someday"
        }
    }
}

/// What Ankur can do with a plan or task from any Planner view: tick a task, say whether he attended a plan,
/// message the agent that keeps either (RSVP only opens that chat with his answer ready; it never writes), and
/// open directions to a plan's place.
@MainActor
@Observable
final class PlannerActions {
    private struct Answer {
        let value: Bool?
    }

    let ticker: TaskTicker
    private let yaad: YaadClient
    private let message: (String, String?) -> Void
    private let reachable: (String) -> Bool
    private let nameOf: (String) -> String
    private var answers: [String: Answer] = [:]

    /// The sheet that is up.
    var sheet: PlannerSheet?
    /// Why the last attendance answer was not saved.
    private(set) var attendedFailure: String?

    /// - Parameters:
    ///   - message: opens the thread of the agent with this id, with the text ready in its composer when given.
    ///   - reachable: whether an agent is still running.
    ///   - nameOf: an agent's name for display.
    init(yaad: YaadClient, message: @escaping (String, String?) -> Void, reachable: @escaping (String) -> Bool, nameOf: @escaping (String) -> String) {
        self.yaad = yaad
        self.message = message
        self.reachable = reachable
        self.nameOf = nameOf
        ticker = TaskTicker { id, done in _ = try await yaad.setDone(done, task: id) }
    }

    /// The agent to message about something owned by `owner`; nil for a source and for a retired agent.
    func agent(for owner: String) -> String? {
        PlanOwner.agent(owner, active: reachable)
    }

    /// An agent's name for display.
    func name(of agent: String) -> String {
        nameOf(agent)
    }

    /// Opens the thread of the agent that keeps something owned by `owner`.
    func messageOwner(_ owner: String) {
        guard let agent = agent(for: owner) else { return }
        sheet = nil
        message(agent, nil)
    }

    /// Opens the keeping agent's chat with "I'm going to ..." or "I'm not going to ..." ready, for Ankur to send.
    func tell(_ plan: Plan, going: Bool, calendar: Calendar = .current) {
        guard let agent = agent(for: plan.owner) else { return }
        sheet = nil
        message(agent, Self.rsvpMessage(plan, going: going, calendar: calendar))
    }

    /// "I'm going to Study block on Fri, Nov 20" or "I'm not going to ...".
    static func rsvpMessage(_ plan: Plan, going: Bool, calendar: Calendar = .current) -> String {
        let day = plan.startAt.formatted(Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).month(.abbreviated).day())
        return "I’m \(going ? "going" : "not going") to \(plan.title) on \(day)"
    }

    /// `plan` with Ankur's unsaved attendance answer over it.
    func shown(_ plan: Plan) -> Plan {
        answers[plan.id].map { plan.answered(attended: $0.value) } ?? plan
    }

    func shown(_ plans: [Plan]) -> [Plan] {
        plans.map(shown)
    }

    /// Records whether Ankur attended `plan` (nil clears it), on screen at once and put back if it is not saved.
    func setAttended(_ attended: Bool?, on plan: Plan) {
        withAnimation(PlannerMotion.fast) {
            answers[plan.id] = Answer(value: attended)
            attendedFailure = nil
            if case .plan(let open) = sheet, open.id == plan.id { sheet = .plan(plan.answered(attended: attended)) }
        }
        Task {
            do {
                _ = try await yaad.setAttended(attended, plan: plan.id)
            } catch {
                withAnimation(Motion.settle) {
                    answers[plan.id] = nil
                    if case .plan(let open) = sheet, open.id == plan.id { sheet = .plan(plan) }
                    attendedFailure = "Couldn’t save attendance: \(error.localizedDescription)"
                }
            }
        }
    }

    func clearAttendedFailure() {
        attendedFailure = nil
    }

    /// Drops the answers Yaad now reports itself, once a reload has them.
    func settle(_ plans: [Plan]) {
        for plan in plans where answers[plan.id].map({ $0.value == plan.attended }) == true {
            answers[plan.id] = nil
        }
    }
}

extension View {
    /// Presents whatever sheet `actions` holds: a plan, a task, a day card or Someday, each in the one anatomy.
    func plannerSheets(actions: PlannerActions, yaad: YaadClient) -> some View {
        sheet(item: Bindable(actions).sheet) { sheet in
            Group {
                switch sheet {
                case .plan(let plan): PlanSheet(plan: plan, actions: actions)
                case .task(let task): PlanTaskSheet(task: task, actions: actions)
                case .day(let day): DayCardSheet(day: day, yaad: yaad, actions: actions)
                case .someday: SomedaySheet(yaad: yaad, actions: actions)
                }
            }
            .fittedSheet()
            .presentationBackground(.thinMaterial)
        }
    }
}

/// Directions to a place in Apple Maps, from its street address.
enum Directions {
    /// `maps://?daddr=` for `place`'s street address; nil when the place has none or its "address" is a call link.
    static func url(to place: PlanPlace?) -> URL? {
        guard let address = place?.address, !Meeting.isLink(address), var parts = URLComponents(string: "maps://") else { return nil }
        parts.queryItems = [URLQueryItem(name: "daddr", value: address)]
        return parts.url
    }
}

/// When a plan is, in words: "Fri, Nov 20" with its clock range, or "Fri, Nov 20 · All day".
func planWhen(_ plan: Plan) -> String {
    let day = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
    if plan.allDay { return "\(plan.startAt.formatted(day)) · All day" }
    guard let end = plan.endAt else { return "\(plan.startAt.formatted(day)), \(Phrase.clock(plan.startAt))" }
    return "\(plan.startAt.formatted(day)), \(Phrase.clock(plan.startAt)) – \(Phrase.clock(end))"
}

extension Plan {
    /// The dot a plan carries: muted when declined, tide when it belongs to a course, sage otherwise.
    var tone: Color {
        if declined { return .inkFaint }
        return hub == nil ? .sage : .tide
    }
}

/// How a plan's bar reads: course tide, otherwise sage, muted and dashed when declined.
struct BarLook {
    let fill: Color
    let line: Color
    let ink: Color
    let dashed: Bool

    init(_ plan: Plan) {
        if plan.declined {
            (fill, line, ink, dashed) = (.bone, .inkFaint, .inkMuted, true)
        } else if plan.hub == nil {
            (fill, line, ink, dashed) = (Color.sage.opacity(0.2), .sageLine, .sageText, false)
        } else {
            (fill, line, ink, dashed) = (Color.tide.opacity(0.16), Color.tide.opacity(0.45), .tideText, false)
        }
    }
}

/// The bottom capsule after a tick: "Checked off" with Undo; or why a tick or an attendance answer was not saved.
struct MarkBanner: View {
    let actions: PlannerActions

    var body: some View {
        let ticker = actions.ticker
        Group {
            if let failure = ticker.failure {
                notice("Couldn’t update the task: \(failure.message)") { ticker.clearFailure() }
            } else if let problem = actions.attendedFailure {
                notice(problem) { actions.clearAttendedFailure() }
            } else if let undo = ticker.undo {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Checked off").font(.footnote.weight(.semibold)).foregroundStyle(.ink)
                        Text(undo.title).font(.caption).foregroundStyle(.inkMuted).lineLimit(1)
                    }
                    Button("Undo") { ticker.undoLast() }
                        .font(.footnote.weight(.semibold))
                        .tint(.sageDeep)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .sensoryFeedback(trigger: ticker.ticks) { _, _ in .success }
        .sensoryFeedback(.error, trigger: ticker.failure) { $1 != nil }
    }

    private func notice(_ text: String, dismiss: @escaping () -> Void) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.danger)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .onTapGesture(perform: dismiss)
    }
}
