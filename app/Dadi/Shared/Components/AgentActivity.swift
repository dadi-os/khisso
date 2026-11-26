import SwiftUI

/// What an agent is doing, as thaali words it: its one loop runs a step, it waits on a helper or another agent
/// after its wake ended, or it rests.
enum AgentState: String, Codable, Sendable, Hashable, CaseIterable {
    case working
    case waiting
    case idle

    /// The word a chip or list names the state with.
    var label: String { rawValue.capitalized }
}

/// What the job ledger adds to the state, as a fact about the job and never a count: the answer time passed with
/// nothing sent, or Ankur stopped the job.
enum AgentMark: Sendable, Hashable {
    case overdue
    case stopped
}

extension AgentRecord.Running {
    /// Working wins over waiting; no loop and no wait is idle.
    var state: AgentState {
        if working { return .working }
        return waitingOn == nil ? .idle : .waiting
    }

    /// `stopped` once the job was stopped, `overdue` when its answer time passed and nothing was sent to the
    /// requester; nil with no job or nothing to flag.
    func mark(at now: Date) -> AgentMark? {
        guard let job else { return nil }
        if job.stopped != nil { return .stopped }
        if let answerBy = job.answerBy, job.told.isEmpty, answerBy < now { return .overdue }
        return nil
    }
}

extension AgentMark {
    /// The flag as a list says it beside the state.
    var word: String {
        switch self {
        case .overdue: "answer overdue"
        case .stopped: "stopped"
        }
    }
}

/// An agent's state as a dot: sage and pulsing while it works, tide while it waits (filled in a header, a ring in
/// a list), grey at rest. A late-ink ring says its job is overdue or stopped; in a header a stopped job takes the
/// whole dot.
struct StateDot: View {
    let state: AgentState
    let mark: AgentMark?
    /// The header's orb: bigger, waiting is filled and a stopped job fills it late-ink.
    var header = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var size: CGFloat { header ? 12 : 9 }

    var body: some View {
        ZStack {
            if state == .working && !reduceMotion {
                Circle()
                    .fill(Color.sage.opacity(0.5))
                    .frame(width: size, height: size)
                    .phaseAnimator([false, true]) { halo, out in
                        halo.scaleEffect(out ? 2.2 : 1).opacity(out ? 0 : 0.6)
                    } animation: { out in out ? .easeOut(duration: 2.4) : nil }
            }
            dot
            if mark != nil && !(header && mark == .stopped) {
                Circle().strokeBorder(Color.lateInk, lineWidth: 1.5).frame(width: size + 6, height: size + 6)
            }
        }
        .frame(width: size + 6, height: size + 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.words(mark))
    }

    @ViewBuilder
    private var dot: some View {
        if header && mark == .stopped {
            Circle().fill(Color.lateInk).frame(width: size, height: size)
        } else {
            switch state {
            case .working: Circle().fill(Color.sage).frame(width: size, height: size)
            case .waiting where header: Circle().fill(Color.tide).frame(width: size, height: size)
            case .waiting: Circle().strokeBorder(Color.tide, lineWidth: 1.5).frame(width: size, height: size)
            case .idle: Circle().fill(Color.inkFaint.opacity(0.55)).frame(width: size, height: size)
            }
        }
    }
}

extension AgentState {
    /// The state as a screen reader says it: "Working", "Waiting, answer overdue", "Idle, stopped".
    func words(_ mark: AgentMark?) -> String {
        switch mark {
        case .overdue: "\(label), answer overdue"
        case .stopped: "\(label), stopped"
        case nil: label
        }
    }
}

/// Thaali's processing mark: three dots flowing left to right, each swelling in
/// at the left, drifting right, then dipping and fading off the end to come
/// back at the start. Reduced motion holds them still mid-flow.
struct ProcessingMark: View {
    /// How much larger than thaali's 22 × 12 mark to draw it.
    var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 22, height: 12)
    static let dot: CGFloat = 3.5
    /// One pass of a dot across the mark, in milliseconds.
    static let flow: Double = 1500

    /// Where dot `index` (of three) is `ms` into the flow: its center, scale
    /// and opacity.
    static func pose(_ index: Int, ms: Double) -> (center: CGPoint, scale: CGFloat, opacity: Double) {
        let p = (ms / flow + Double(index) / 3).truncatingRemainder(dividingBy: 1)
        let rise = sin(.pi * p)
        let drop = p > 0.72 ? pow((p - 0.72) / 0.28, 2) : 0
        return (CGPoint(x: 2 + p * (size.width - 4), y: size.height / 2 + drop * 4), 0.55 + 0.45 * rise, rise)
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let ms = reduceMotion ? Self.flow * 0.3 : context.date.timeIntervalSinceReferenceDate * 1000
            Canvas { canvas, _ in
                canvas.scaleBy(x: scale, y: scale)
                for index in 0..<3 {
                    let pose = Self.pose(index, ms: ms)
                    let r = Self.dot / 2 * pose.scale
                    canvas.fill(
                        Circle().path(in: CGRect(x: pose.center.x - r, y: pose.center.y - r, width: r * 2, height: r * 2)),
                        with: .color(.sageDeep.opacity(pose.opacity))
                    )
                }
            }
        }
        .frame(width: Self.size.width * scale, height: Self.size.height * scale)
        .accessibilityHidden(true)
    }
}

/// Thaali's working sheen: one turning angle drives a beam of light sweeping
/// through the surface and a ring of light running round its edge, so a busy
/// pill or row reads as working at the level of the surface itself.
private struct WorkingSheen<S: InsettableShape>: ViewModifier {
    let active: Bool
    let shape: S
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One turn, in seconds.
    private let turn = 2.4

    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation(paused: reduceMotion)) { context in
                let seconds = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                let angle = Angle.degrees(seconds.truncatingRemainder(dividingBy: turn) / turn * 360 - 90)
                content
                    .background {
                        shape.fill(gradient(from: angle, peak: 0.2, clearUntil: 0.62))
                    }
                    .overlay {
                        shape.strokeBorder(gradient(from: angle, peak: 0.9, clearUntil: 0.58), lineWidth: 1)
                    }
                    .clipShape(shape)
            }
        } else {
            content
        }
    }

    private func gradient(from angle: Angle, peak: Double, clearUntil: Double) -> AngularGradient {
        AngularGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: clearUntil),
                .init(color: .sage.opacity(peak), location: 0.84),
                .init(color: .clear, location: 1),
            ],
            center: .center,
            startAngle: angle,
            endAngle: angle + .degrees(360)
        )
    }
}

extension View {
    /// Runs thaali's working sheen across `shape` while `active`.
    func workingSheen<S: InsettableShape>(_ active: Bool, in shape: S) -> some View {
        modifier(WorkingSheen(active: active, shape: shape))
    }
}

/// The thread's one activity label, as thaali words it: `working` with what the wake has done so far, `waiting on`
/// its targets once the wake ended with a watch, nil at rest.
enum ActivityLabel {
    /// The most targets the label names before it counts the rest.
    static let named = 2

    static func text(_ running: AgentRecord.Running, counts: WakeCounts?) -> String? {
        if running.working {
            let calls = counts?.toolCalls ?? 0
            return calls > 0 ? "working · \(calls) tool \(calls == 1 ? "call" : "calls")" : "working"
        }
        guard let waiting = running.waitingOn else { return nil }
        let more = waiting.targets.count - named
        return "waiting on \(waiting.targets.prefix(named).joined(separator: ", "))\(more > 0 ? " +\(more)" : "")"
    }
}

/// Thaali's activity pill: soft glass floating above the composer while the agent works or waits, the one place a
/// thread shows what its agent is doing. Working runs the sheen on the pill itself; waiting is the same glass at
/// rest.
struct ActivityPill: View {
    let running: AgentRecord.Running
    /// What the running wake has done so far.
    let counts: WakeCounts?
    /// The glass namespace shared with whatever splits off from the pill (the
    /// scroll-to-newest caret), so the two flow apart and back as one glass.
    let glass: Namespace.ID

    /// The pill's height, which the caret beside it matches.
    static let height: CGFloat = 40

    var body: some View {
        ZStack {
            if let label = ActivityLabel.text(running, counts: counts) {
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(0.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(running.working ? Color.sageText : .tideText)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 19)
                    .frame(height: Self.height)
                    .overlay(Capsule().strokeBorder((running.working ? Color.sageLine : Color.tide).opacity(0.48), lineWidth: 1))
                    .workingSheen(running.working, in: Capsule())
                    .glassEffect(.regular.tint(Color.bone.opacity(0.6)), in: .capsule)
                    .glassEffectID("activity", in: glass)
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityAddTraits(.updatesFrequently)
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .animation(Motion.settle, value: ActivityLabel.text(running, counts: counts))
        .allowsHitTesting(false)
    }
}
