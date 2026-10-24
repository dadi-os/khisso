import SwiftUI

/// The agent's scheduled messages, both the ones it sends and the ones it
/// receives, each with its next run, repeat and message, editable in place as
/// in thaali. Absent when the agent has none.
struct ScheduleSection: View {
    let hath: HathClient
    let agentId: String
    let schedules: [ScheduledMessage]
    let nameOf: (String) -> String
    /// Reads the schedules again after one is changed or cancelled.
    let changed: () async -> Void

    @State private var editing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(schedules) { schedule in
                ScheduleRow(
                    hath: hath,
                    schedule: schedule,
                    outgoing: schedule.fromAgentId == agentId,
                    other: nameOf(schedule.fromAgentId == agentId ? schedule.toAgentId : schedule.fromAgentId),
                    editing: editing == schedule.id,
                    edit: { withAnimation(Motion.snap) { editing = schedule.id } },
                    done: { withAnimation(Motion.snap) { editing = nil } },
                    changed: changed
                )
            }
        }
    }
}

/// One schedule: who it goes to or comes from, when it next runs, how it
/// repeats and its message, or its editor.
private struct ScheduleRow: View {
    let hath: HathClient
    let schedule: ScheduledMessage
    let outgoing: Bool
    let other: String
    let editing: Bool
    let edit: () -> Void
    let done: () -> Void
    let changed: () async -> Void

    /// Repeat choices as minutes; nil is a one-shot.
    private static let presets: [(minutes: Int?, label: String)] = [(nil, "Once"), (60, "Hourly"), (1440, "Daily"), (10080, "Weekly")]

    @State private var runAt = Date()
    @State private var minutes: Int?
    @State private var content = ""
    @State private var confirmCancel = false
    @State private var working = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(outgoing ? "To" : "From").font(.footnote).foregroundStyle(.inkFaint)
                Text(other).font(.footnote.weight(.semibold)).foregroundStyle(.ink).lineLimit(1)
                Spacer()
                if !editing {
                    Button("Edit", action: begin).font(.footnote).foregroundStyle(.sageDeep)
                }
            }
            if editing {
                editor
            } else {
                Text("\(schedule.runAt.formatted(date: .abbreviated, time: .shortened)) · \(schedule.runAt.formatted(.relative(presentation: .named))) · \(Self.label(schedule.intervalMinutes))")
                    .font(.footnote)
                    .foregroundStyle(.ink)
                Text(schedule.content)
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(editing ? Color.sage.opacity(0.08) : .clear, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(editing ? Color.sageLine : .sageLine.opacity(0.4), lineWidth: 1))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Next run", selection: $runAt, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                .font(.footnote)
            Picker("Repeat", selection: $minutes) {
                ForEach(options, id: \.minutes) { Text($0.label).tag($0.minutes) }
            }
            .pickerStyle(.segmented)
            TextField("Message", text: $content, axis: .vertical)
                .lineLimit(2...6)
                .font(.footnote)
                .padding(10)
                .background(.sage.opacity(0.08), in: .rect(cornerRadius: 10, style: .continuous))
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.danger)
            }
            HStack {
                Button(confirmCancel ? "Confirm cancel" : "Cancel schedule", role: .destructive) {
                    if confirmCancel { cancel() } else { confirmCancel = true }
                }
                .font(.footnote)
                .disabled(working)
                Spacer()
                Button("Discard", action: done).font(.footnote).foregroundStyle(.inkMuted)
                Button("Save", action: save)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.glass)
                    .disabled(change == nil || working)
            }
        }
    }

    /// The presets, plus this schedule's own repeat when it is not one of them.
    private var options: [(minutes: Int?, label: String)] {
        Self.presets.contains { $0.minutes == schedule.intervalMinutes }
            ? Self.presets
            : Self.presets + [(schedule.intervalMinutes, Self.label(schedule.intervalMinutes))]
    }

    /// What editing has changed, or nil when nothing has or the message is empty.
    private var change: PatchScheduleRequest? {
        let words = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return nil }
        var request = PatchScheduleRequest()
        if abs(runAt.timeIntervalSince(schedule.runAt)) >= 60 { request.runAt = runAt }
        if minutes != schedule.intervalMinutes { request.repeats = minutes.map { .every(minutes: $0) } ?? .once }
        if words != schedule.content { request.content = words }
        return request.runAt == nil && request.repeats == nil && request.content == nil ? nil : request
    }

    private func begin() {
        runAt = schedule.runAt
        minutes = schedule.intervalMinutes
        content = schedule.content
        confirmCancel = false
        problem = nil
        edit()
    }

    private func save() {
        guard let change else { return }
        run { _ = try await hath.patchSchedule(schedule.id, change) }
    }

    private func cancel() {
        run { try await hath.cancelSchedule(schedule.id) }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        working = true
        problem = nil
        Task {
            defer { working = false }
            do {
                try await action()
                done()
                await changed()
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    /// A repeat in words: "Once", "Daily", "Every 3 days", "Every 2 h", "Every 45 min".
    static func label(_ minutes: Int?) -> String {
        guard let minutes else { return "Once" }
        if let preset = presets.first(where: { $0.minutes == minutes }) { return preset.label }
        if minutes % 1440 == 0 { return "Every \(minutes / 1440) days" }
        if minutes % 60 == 0 { return "Every \(minutes / 60) h" }
        return "Every \(minutes) min"
    }
}
