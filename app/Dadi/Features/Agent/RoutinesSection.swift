import SwiftUI

/// The agent's routines and reminders in an inset card. There is no editor: a routine is its agent's to change, so
/// the one control is Cancel, which asks once, in place. The card is hidden once read and empty, and then there is no
/// message footer either.
struct RoutinesSection: View {
    /// What the card is showing: its content once read, a placeholder while it loads, or why it failed.
    enum Feed: Equatable {
        case loading
        case failed(String)
        case ready(Routines)
    }

    let feed: Feed
    /// Cancels a routine; rejects with Hath's reason, which the row shows.
    let cancelRoutine: (String) async throws -> Void
    let cancelReminder: (String) async throws -> Void
    /// Opens the agent's thread.
    let message: () -> Void
    let now: Date

    /// Whether the card is drawn at all: always while unread, else only when something can be cancelled.
    static func shown(_ feed: Feed) -> Bool {
        guard case .ready(let routines) = feed else { return true }
        return !RoutineFormat.active(routines.routines).isEmpty || !routines.reminders.isEmpty
    }

    /// The card's count: "2 routines · 1 reminder".
    static func count(_ routines: Routines) -> String {
        [
            RoutineFormat.active(routines.routines).count,
            routines.reminders.count,
        ].enumerated().compactMap { index, n in
            n == 0 ? nil : "\(n) \(index == 0 ? (n == 1 ? "routine" : "routines") : (n == 1 ? "reminder" : "reminders"))"
        }
        .joined(separator: " · ")
    }

    var body: some View {
        if Self.shown(feed) {
            InsetCard(title: "Routines & reminders", count: countText) {
                switch feed {
                case .loading:
                    SkeletonRows(count: 1, height: 14)
                case .failed(let reason):
                    Text(reason).font(.system(size: 13)).foregroundStyle(.danger).textSelection(.enabled)
                case .ready(let routines):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(RoutineFormat.active(routines.routines)) { routine in
                            RoutineRow(title: routine.title, detail: routine.procedure, cadence: RoutineFormat.cadence(routine), when: RoutineFormat.runs(routine, now: now), warning: "It will not run again.", confirm: "Cancel routine") {
                                try await cancelRoutine(routine.id)
                            }
                            .transition(.opacity)
                        }
                        ForEach(routines.reminders) { reminder in
                            RoutineRow(title: reminder.note, detail: nil, cadence: "Check back", when: RoutineFormat.reminderWhen(reminder), warning: "The agent will not be woken for it.", confirm: "Cancel reminder") {
                                try await cancelReminder(reminder.id)
                            }
                            .transition(.opacity)
                        }
                        Button(action: message) {
                            Text("To change or add one, message the agent.").font(.system(size: 12.5)).foregroundStyle(.sageDeep)
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 32)
                    }
                    .animation(Motion.settle, value: routines)
                }
            }
        }
    }

    private var countText: String? {
        guard case .ready(let routines) = feed else { return nil }
        return Self.count(routines)
    }
}

/// One routine or reminder as an expander card: collapsed, its title, cadence and when it runs next; opened, the whole
/// procedure and the one control, Cancel, which asks once.
private struct RoutineRow: View {
    let title: String
    /// A routine's procedure in full; nil for a reminder.
    let detail: String?
    let cadence: String
    let when: String
    /// What cancelling means, shown with the confirm.
    let warning: String
    let confirm: String
    let cancel: () async throws -> Void

    @State private var open = false
    @State private var confirming = false
    @State private var pending = false
    @State private var problem: String?
    @State private var cancelled = 0

    var body: some View {
        Expandable(isOpen: $open, icon: detail == nil ? "bell" : "clock.arrow.circlepath") {
            Text(title).lineLimit(2)
        } secondary: {
            VStack(alignment: .leading, spacing: 1) {
                Text(cadence)
                Text(when)
            }
        } trailing: {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if let detail { AgentMarkdown(source: detail, compact: true) }
                if confirming {
                    HStack(spacing: 8) {
                        Text(warning).font(.system(size: 12.5)).foregroundStyle(.inkMuted)
                        Spacer(minLength: 4)
                        Button(confirm, role: .destructive, action: run).buttonStyle(.bordered).disabled(pending)
                        Button("Keep") { confirming = false }.buttonStyle(.plain).foregroundStyle(.inkMuted).frame(minHeight: 44)
                    }
                    .controlSize(.small)
                } else {
                    Button { confirming = true } label: {
                        Text("Cancel").font(.footnote.weight(.semibold)).foregroundStyle(.inkMuted).frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel \(title)")
                }
                if let problem { Text(problem).font(.system(size: 12.5)).foregroundStyle(.danger).textSelection(.enabled) }
            }
        }
        .animation(Motion.snap, value: confirming)
        .sensoryFeedback(.success, trigger: cancelled)
    }

    private func run() {
        pending = true
        problem = nil
        Task {
            defer { pending = false }
            do {
                try await cancel()
                cancelled += 1
            } catch {
                problem = error.localizedDescription
                confirming = false
            }
        }
    }
}
