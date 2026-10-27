import SwiftUI
import UIKit

/// What Ankur can do with a session from any timeline view: mark it
/// Completed or take the mark back (the only write the app makes, shown at
/// once and put back with Yaad's reason if it is not saved, with an undo
/// after each mark), message the agent that keeps it, or tell Dadi about it
/// when no agent does or the one that recorded it has since retired (as the
/// one-shot workers do), and open directions to where it happens.
@MainActor
@Observable
final class SessionActions {
    /// A mark Yaad did not save: which session, which way, and why.
    struct Failure: Equatable {
        let id: String
        let title: String
        let completed: Bool
        let message: String
    }

    /// The last mark, offered back for a few seconds.
    struct Undo: Equatable {
        let item: TimelineItem
        let completed: Bool
        let at = UUID()
    }

    /// How long a mark's undo stays up.
    static let undoFor: Duration = .seconds(4)

    private let yaad: YaadClient
    private let message: (String) -> Void
    private let tellDadi: (TimelineItem) -> Void
    private let reachable: (String) -> Bool

    /// Completed or not as Ankur last marked each session, shown over what
    /// Yaad returns until his save lands.
    private(set) var marks: [String: Bool] = [:]
    private(set) var failure: Failure?
    private(set) var undo: Undo?
    /// Bumped on each mark, for its haptic.
    private(set) var marked = 0
    /// The session whose sheet is up.
    var opened: TimelineItem?

    /// - Parameters:
    ///   - message: opens the thread of the agent with this id.
    ///   - tellDadi: opens Talk to Dadi about this session.
    ///   - reachable: whether an agent can still be messaged.
    init(yaad: YaadClient, message: @escaping (String) -> Void, tellDadi: @escaping (TimelineItem) -> Void, reachable: @escaping (String) -> Bool) {
        self.yaad = yaad
        self.message = message
        self.tellDadi = tellDadi
        self.reachable = reachable
    }

    /// The agent to message about `item`: the one that keeps it, while it can
    /// still be messaged; nil means Dadi.
    func owner(of item: TimelineItem) -> String? {
        item.ownerAgent.flatMap { reachable($0) ? $0 : nil }
    }

    /// `items` with Ankur's unsaved marks over them.
    func shown(_ items: [TimelineItem]) -> [TimelineItem] {
        items.map(shown)
    }

    /// `item` with Ankur's unsaved mark over it, if he made one.
    func shown(_ item: TimelineItem) -> TimelineItem {
        marks[item.id].map { item.marked(completed: $0) } ?? item
    }

    /// True when `item` can be marked: it is a dated session that was not cancelled.
    func markable(_ item: TimelineItem) -> Bool {
        item.occurrenceDate != nil && !item.cancelled
    }

    /// Marks `item` completed if it is not and takes the mark back if it is,
    /// on screen at once, then saves it.
    func toggle(_ item: TimelineItem) {
        let current = marks[item.id] ?? item.completed
        set(!current, on: item)
    }

    /// Puts the last mark back the other way.
    func undoLast() {
        guard let undo else { return }
        self.undo = nil
        set(!undo.completed, on: undo.item, offeringUndo: false)
    }

    /// Opens the thread of the agent that keeps `item`, or Talk to Dadi
    /// about it when no agent that can be messaged does.
    func messageOwner(_ item: TimelineItem) {
        opened = nil
        if let agent = owner(of: item) { message(agent) } else { tellDadi(item) }
    }

    func clearFailure() {
        failure = nil
    }

    private func set(_ completed: Bool, on item: TimelineItem, offeringUndo: Bool = true) {
        guard let date = item.occurrenceDate, !item.cancelled else { return }
        withAnimation(Motion.pop) {
            marks[item.id] = completed
            failure = nil
            marked += 1
            undo = offeringUndo ? Undo(item: item, completed: completed) : nil
        }
        if let shown = undo {
            Task {
                do { try await Task.sleep(for: Self.undoFor) } catch { return }
                if undo == shown { withAnimation(Motion.settle) { undo = nil } }
            }
        }
        Task {
            do {
                _ = try await yaad.setCompleted(completed, plan: item.planId, on: date)
            } catch {
                guard marks[item.id] == completed else { return }
                withAnimation(Motion.settle) {
                    marks[item.id] = nil
                    undo = nil
                    failure = Failure(id: item.id, title: item.title, completed: completed, message: error.localizedDescription)
                }
            }
        }
    }

    /// Drops the marks Yaad now reports itself, once a reload has them.
    func settle(_ items: [TimelineItem]) {
        for item in items where marks[item.id] == item.completed {
            marks[item.id] = nil
        }
    }
}

/// Directions to a place in Apple Maps, from its street address.
enum Directions {
    /// `maps://?daddr=` for `place`'s address; nil when the place has none.
    static func url(to place: TimelinePlace?) -> URL? {
        guard let address = place?.address, var parts = URLComponents(string: "maps://") else { return nil }
        parts.queryItems = [URLQueryItem(name: "daddr", value: address)]
        return parts.url
    }
}

/// A session in words for the pasteboard: title, when, where, and its notes.
func sessionDetails(_ item: TimelineItem) -> String {
    var lines = [item.title, sessionWhen(item)]
    if let place = item.place {
        lines.append([place.title, place.room.map { "room \($0)" }, place.address].compactMap { $0 }.joined(separator: ", "))
    }
    lines.append(contentsOf: item.notes.map(\.title))
    return lines.joined(separator: "\n")
}

/// When a session is, in words: "Thu Oct 29, 1:00 – 2:20 PM", "Due Wed Nov 4, 11:59 PM", or "Someday".
func sessionWhen(_ item: TimelineItem) -> String {
    let day = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
    if let start = item.startAt {
        if item.allDay { return start.formatted(day) }
        let range = item.endAt.map { "\(start.formatted(day)), \(start.formatted(date: .omitted, time: .shortened)) – \($0.formatted(date: .omitted, time: .shortened))" }
        return range ?? "\(start.formatted(day)), \(start.formatted(date: .omitted, time: .shortened))"
    }
    if let due = item.dueAt {
        return item.allDay ? "Due \(due.formatted(day))" : "Due \(due.formatted(day)), \(due.formatted(date: .omitted, time: .shortened))"
    }
    return "Someday"
}

/// The long-press menu every session row offers.
struct SessionMenu: View {
    let item: TimelineItem
    let actions: SessionActions

    @Environment(\.openURL) private var openURL

    var body: some View {
        if actions.markable(item) {
            Button { actions.toggle(item) } label: {
                Label(item.completed ? "Undo completed" : "Mark completed", systemImage: item.completed ? "arrow.uturn.backward" : "checkmark.circle")
            }
        }
        Button { actions.messageOwner(item) } label: {
            Label(actions.owner(of: item).map { "Message \($0)" } ?? "Tell Dadi", systemImage: "bubble.left")
        }
        if let url = Directions.url(to: item.place) {
            Button { openURL(url) } label: { Label("Directions", systemImage: "map") }
        }
        Button { actions.opened = item } label: {
            Label(item.notes.isEmpty ? "Session notes" : "Session notes · \(item.notes.count)", systemImage: "note.text")
        }
        Button { UIPasteboard.general.string = sessionDetails(item) } label: {
            Label("Copy details", systemImage: "doc.on.doc")
        }
    }
}

/// A session row's gestures: tap opens its sheet, a swipe right marks it
/// Completed, a swipe left messages its owner, and a long press opens its
/// menu. The row follows the finger and shows what letting go will do; its
/// drag wins over the page's day swipe because it sits on the row, and the
/// drawer's left-edge strip lies over both.
struct SessionGestures: ViewModifier {
    let item: TimelineItem
    let actions: SessionActions
    /// Corner radius of the row, for the label revealed behind it.
    var radius: CGFloat = 12

    @State private var offset: CGFloat = 0

    /// How far a swipe travels before letting go acts.
    private let reach: CGFloat = 80

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: offset > 0 ? .leading : .trailing) {
                if offset != 0 {
                    Text(offset > 0 ? (item.completed ? "Undo" : "Completed") : "Message")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(offset > 0 ? Color.bone : .ink)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: offset > 0 ? .leading : .trailing)
                        .background(offset > 0 ? Color.sageDeep : .boneRaised, in: .rect(cornerRadius: radius, style: .continuous))
                        .opacity(min(1, abs(offset) / reach))
                }
            }
            .contentShape(.rect)
            .onTapGesture { actions.opened = item }
            .contextMenu { SessionMenu(item: item, actions: actions) }
            .gesture(
                DragGesture(minimumDistance: 16)
                    .onChanged { drag in
                        guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                        offset = drag.translation.width > 0 && !actions.markable(item) ? 0 : drag.translation.width
                    }
                    .onEnded { _ in
                        if offset >= reach { actions.toggle(item) }
                        if offset <= -reach { actions.messageOwner(item) }
                        withAnimation(Motion.snap) { offset = 0 }
                    }
            )
            .sensoryFeedback(.impact(flexibility: .soft), trigger: abs(offset) >= reach)
    }
}

extension View {
    /// Tap, swipe and long-press for a session row; see `SessionGestures`.
    func sessionGestures(_ item: TimelineItem, actions: SessionActions, radius: CGFloat = 12) -> some View {
        modifier(SessionGestures(item: item, actions: actions, radius: radius))
    }
}

/// The bottom capsule after a mark: what was marked, with Undo; or why a
/// mark was not saved.
struct MarkBanner: View {
    let actions: SessionActions

    var body: some View {
        Group {
            if let failure = actions.failure {
                Label("\(failure.title) wasn't marked \(failure.completed ? "completed" : "not completed"): \(failure.message)", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .onTapGesture { actions.clearFailure() }
            } else if let undo = actions.undo {
                HStack(spacing: 12) {
                    Text(undo.completed ? "Completed \(undo.item.title)" : "Took back \(undo.item.title)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.ink)
                        .lineLimit(1)
                    Button("Undo") { actions.undoLast() }
                        .font(.footnote.weight(.semibold))
                        .tint(.sageDeep)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .sensoryFeedback(trigger: actions.marked) { _, _ in .success }
        .sensoryFeedback(.error, trigger: actions.failure) { $1 != nil }
    }
}

/// A session's sheet: kind and series, title and when, where with Go to
/// Apple Maps, its series marks, its notes and body, Mark completed, and a
/// message to its owner.
struct SessionSheet: View {
    let item: TimelineItem
    let actions: SessionActions

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text([item.kind?.label, item.recurrence].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.sageText)
                Text(item.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(item.completed ? .inkMuted : .ink)
                    .strikethrough(item.cancelled, color: .inkFaint)
                Text(item.cancelled ? "Cancelled · \(sessionWhen(item))" : sessionWhen(item))
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
            }
            if let place = item.place {
                Button {
                    if let url = Directions.url(to: place) { openURL(url) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.sageDeep)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.room.map { "\(place.title) · Room \($0)" } ?? place.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.ink)
                            if let address = place.address {
                                Text(address).font(.caption).foregroundStyle(.inkMuted)
                            }
                        }
                        Spacer(minLength: 0)
                        if place.address != nil {
                            Text("Go").font(.subheadline.weight(.semibold)).foregroundStyle(.sageDeep)
                        }
                    }
                    .padding(14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .disabled(place.address == nil)
                .accessibilityLabel(place.address == nil ? place.title : "Directions to \(place.title) in Apple Maps")
            }
            if let series = item.series {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 3) {
                        ForEach(0..<series.total, id: \.self) { index in
                            Capsule()
                                .fill(index < series.completed ? Color.sageDeep : .rule)
                                .frame(height: 6)
                        }
                    }
                    Text("Completed \(series.completed) of \(series.total) so far")
                        .font(.caption)
                        .foregroundStyle(.inkMuted)
                }
            }
            if !item.notes.isEmpty || item.body != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This session").font(.caption.weight(.semibold)).foregroundStyle(.sageText)
                    ForEach(item.notes) { note in
                        Text(note.title).font(.callout).foregroundStyle(.ink)
                    }
                    if let body = item.body {
                        Text(body).font(.callout).foregroundStyle(.inkMuted)
                    }
                }
            }
            if actions.markable(item) {
                Button { actions.toggle(item) } label: {
                    Label(item.completed ? "Completed" : "Mark completed", systemImage: item.completed ? "checkmark.circle.fill" : "circle")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(item.completed ? .sage : .sageDeep)
                .controlSize(.large)
                .accessibilityHint(item.completed ? "Takes the mark back" : "")
            }
            Button { actions.messageOwner(item) } label: {
                Text(actions.owner(of: item).map { "Message \($0)" } ?? "Tell Dadi")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .padding(24)
        .animation(Motion.settle, value: item)
    }
}
