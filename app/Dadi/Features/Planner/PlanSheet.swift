import SwiftUI

/// A plan's sheet in the shared detail anatomy: its situation ("Now · 12 min left", "Ended 8 h ago · Attended"), the
/// facts in a fixed order, ONE action rail (Attended | Didn't attend saves; Going | Not going opens the agent's chat
/// with Ankur's answer ready and never writes; Message agent; Join call), and its notes.
struct PlanSheet: View {
    let plan: Plan
    let actions: PlannerActions

    @Environment(\.openURL) private var openURL

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .animation(Motion.settle, value: plan)
    }

    private func content(now: Date) -> some View {
        let state = PlanTime.state(plan, now: now, nextID: PlanTime.nextPlanID([plan], now: now))
        let agent = actions.agent(for: plan.owner)
        let started = !plan.declined && !plan.allDay && plan.startAt <= now
        let tellable = agent != nil && !plan.declined && !(plan.endAt.map { $0 <= now } ?? false)
        let items = rail(started: started, tellable: tellable, agent: agent)
        let notes = ([plan.body] + plan.notes.map(\.title)).compactMap { $0 }.filter { !$0.isEmpty }
        return DetailSheet(title: plan.title, hasRail: !items.isEmpty, hasSections: !notes.isEmpty) {
            situation(now: now, state: state)
        } facts: {
            facts(agent: agent)
        } rail: {
            ActionRail(items: items)
            if tellable, let agent {
                Text("Going and Not going open \(actions.name(of: agent))’s chat with your answer ready.")
                    .font(.caption)
                    .foregroundStyle(.inkFaint)
            }
        } sections: {
            InsetCard(title: "Notes") {
                ForEach(Array(notes.enumerated()), id: \.offset) { _, text in
                    Text(text).font(.callout).foregroundStyle(.ink).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func situation(now: Date, state: TimeState) -> some View {
        let label: (String, SituationTone, Bool) = {
            if plan.declined { return ("Declined", .rest, false) }
            if plan.attended == true { return ("Attended", .live, true) }
            if plan.attended == false { return ("Didn’t attend", .rest, false) }
            return (PlanTime.status(plan, now: now, state: state), state == .now ? .live : state == .past ? .rest : .wait, false)
        }()
        return SituationLine(tone: label.1, text: label.0, done: label.2)
    }

    @ViewBuilder
    private func facts(agent: String?) -> some View {
        let timed = !plan.allDay && plan.endAt != nil
        FactRow(label: "Date", value: plan.startAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        if timed, let end = plan.endAt {
            FactRow(label: "Time", value: "\(Phrase.clock(plan.startAt)) – \(Phrase.clock(end))")
            FactRow(label: "Length", value: Phrase.duration(end.timeIntervalSince(plan.startAt)))
        } else {
            FactRow(label: "Time", value: plan.allDay ? "All day" : Phrase.clock(plan.startAt))
        }
        if let there = PlanZone.plannedClock(plan) { FactRow(label: "Local time", value: there, wrap: true) }
        if let place = plan.place, !(plan.street == nil && place.room == nil && meetingLink(plan) != nil) {
            let line = place.room.map { "\(place.title) · room \($0)" } ?? place.title
            TapRow(label: "Where", value: plan.street.map { "\(line)\n\($0)" } ?? line, open: Directions.url(to: place), copy: plan.street, copyTitle: "Copy address", hint: "Opens Apple Maps. Long press to copy the address.")
        }
        if let call = meetingLink(plan) {
            TapRow(label: call.service, value: call.host, open: call.url, copy: call.url.absoluteString, copyTitle: "Copy link", hint: "Opens the call. Long press to copy the link.", glyph: "video", wrap: false)
        }
        if let hub = plan.hub, hub.title != plan.title { FactRow(label: "Course", value: hub.title) }
        if let agent { FactRow(label: "Kept by", value: actions.name(of: agent)) }
        if let rsvp = plan.rsvp { FactRow(label: "Going", value: rsvp == .yes ? "Yes" : "No, declined") }
        if let attended = plan.attended { FactRow(label: "Attended", value: attended ? "Yes, you were there" : "No, you were not") }
    }

    /// Every action in one rail, in a fixed order: Attended | Didn't attend once the plan has started, Going | Not going
    /// while an agent keeps it and it has not ended, Message agent, and Join call for a virtual plan.
    private func rail(started: Bool, tellable: Bool, agent: String?) -> [RailItem] {
        var items: [RailItem] = []
        if started { items.append(.choice(first: "Attended", second: "Didn’t attend", selection: plan.attended) { actions.setAttended($0, on: plan) }) }
        if tellable { items.append(.choice(first: "Going", second: "Not going", selection: plan.rsvp.map { $0 == .yes }) { if let going = $0 { actions.tell(plan, going: going) } }) }
        if agent != nil { items.append(.action(title: "Message agent", symbol: "bubble.left") { actions.messageOwner(plan.owner) }) }
        if let call = meetingLink(plan) { items.append(.action(title: "Join call", symbol: "video", emphasis: true) { openURL(call.url) }) }
        return items
    }
}

/// A fact that is its own interaction: tapping it opens its URL (Apple Maps for Where, the call for Join), a trailing
/// glyph says so, and a long press offers its copy action with a brief "Copied" in place of the glyph.
private struct TapRow: View {
    let label: String
    let value: String
    let open: URL?
    /// What the long press copies; nil when there is nothing to copy.
    let copy: String?
    let copyTitle: String
    let hint: String
    var glyph = "arrow.up.right"
    var wrap = true

    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        Button { if let open { openURL(open) } } label: {
            HStack(alignment: .top, spacing: 8) {
                FactRow(label: label, value: value, wrap: wrap, long: wrap)
                if open != nil {
                    Group {
                        if copied { Text("Copied").font(.caption.weight(.semibold)) } else { Image(systemName: glyph).font(.system(size: 12, weight: .semibold)) }
                    }
                    .foregroundStyle(copied ? Color.sageDeep : .inkMuted)
                    .frame(minWidth: 24, minHeight: 32)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(open != nil)
        .contextMenu {
            if let copy {
                Button {
                    UIPasteboard.general.string = copy
                    withAnimation(Motion.snap) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation(Motion.snap) { copied = false }
                    }
                } label: { Label(copyTitle, systemImage: "doc.on.doc") }
            }
        }
        .accessibilityHint(open == nil ? "" : hint)
    }
}
