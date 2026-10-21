import SwiftUI

/// The timeline opens on the day planner, the only view that shows a single
/// day. Upcoming shows what's next with a live countdown, a week strip, and the
/// next two weeks of Yaad's plans by day; its + adds to them in plain words,
/// which Yaad reads into plans.
struct TimelinePage: View {
    let yaad: YaadClient

    /// The two ways to look at the timeline.
    private enum Mode: String, CaseIterable {
        case day = "Day"
        case upcoming = "Upcoming"
    }

    @State private var mode: Mode = .day

    @State private var plans: [PlanNode] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var adding = false
    @Namespace private var pill

    /// How far ahead the agenda reaches.
    private let horizon = 14

    var body: some View {
        VStack(spacing: 12) {
            Picker("View", selection: $mode.animation(Motion.settle)) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .padding(.horizontal, 20)
            switch mode {
            case .day:
                PlannerDay(yaad: yaad)
                    .transition(.opacity)
            case .upcoming:
                upcoming
                    .transition(.opacity)
            }
        }
        .navigationTitle("Timeline")
    }

    private var upcoming: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let next = plans.first(where: { ($0.occurredAt ?? .distantPast) > .now }) {
                        NextUp(plan: next)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    weekStrip(reader)
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.danger)
                    }
                    if loaded && plans.isEmpty && error == nil {
                        ContentUnavailableView("Nothing planned", systemImage: "calendar", description: Text("The next two weeks are open. Tap + to add something."))
                            .foregroundStyle(.inkMuted)
                            .padding(.top, 40)
                    }
                    ForEach(days, id: \.self) { day in
                        let dayPlans = plans(on: day)
                        if !dayPlans.isEmpty {
                            DaySection(day: day, plans: dayPlans)
                                .id(day)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .animation(Motion.settle, value: plans)
            }
            .refreshable { await load() }
        }
        .overlay(alignment: .bottomTrailing) {
            Button { adding = true } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
            .padding(24)
            .accessibilityLabel("Add to the timeline")
        }
        .sheet(isPresented: $adding) {
            QuickAdd(yaad: yaad) { Task { await load() } }
                .presentationDetents([.medium])
                .presentationBackground(.thinMaterial)
        }
        .task { await load() }
    }

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<horizon).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    private func plans(on day: Date) -> [PlanNode] {
        plans.filter { plan in plan.occurredAt.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false }
    }

    private func weekStrip(_ reader: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let selected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                    let busy = !plans(on: day).isEmpty
                    Button {
                        withAnimation(Motion.snap) { selectedDay = day }
                        withAnimation(Motion.settle) { reader.scrollTo(day, anchor: .top) }
                    } label: {
                        VStack(spacing: 4) {
                            Text(day, format: .dateTime.weekday(.narrow))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(selected ? Color.bone.opacity(0.8) : .inkFaint)
                            Text(day, format: .dateTime.day())
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .foregroundStyle(selected ? Color.bone : .ink)
                            Circle()
                                .fill(selected ? Color.bone : .clay)
                                .frame(width: 5, height: 5)
                                .opacity(busy ? 1 : 0)
                        }
                        .frame(width: 46, height: 70)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.sageDeep)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .scrollIndicators(.hidden)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .sensoryFeedback(.selection, trigger: selectedDay)
    }

    private func load() async {
        let start = Calendar.current.startOfDay(for: .now)
        guard let end = Calendar.current.date(byAdding: .day, value: horizon, to: start) else { return }
        do {
            let fetched = try await yaad.plans(from: start, to: end)
            plans = fetched.sorted { ($0.occurredAt ?? .distantFuture) < ($1.occurredAt ?? .distantFuture) }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

/// The next plan, large, with a countdown that ticks without updates.
private struct NextUp: View {
    let plan: PlanNode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("NEXT UP", systemImage: "sparkle")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.sageText)
            Text(plan.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.ink)
                .lineLimit(3)
            if let start = plan.occurredAt {
                HStack(alignment: .firstTextBaseline) {
                    Text(start, format: plan.detail.allDay ? .dateTime.weekday(.wide).month().day() : .dateTime.weekday(.wide).hour().minute())
                        .font(.callout)
                        .foregroundStyle(.inkMuted)
                    Spacer()
                    if !plan.detail.allDay && start.timeIntervalSinceNow < 86_400 {
                        Text(timerInterval: Date.now...start, countsDown: true)
                            .font(.title.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.sageDeep)
                            .contentTransition(.numericText(countsDown: true))
                    } else {
                        Text(start, style: .relative)
                            .font(.headline)
                            .foregroundStyle(.sageDeep)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [.sage.opacity(0.22), .sageLine.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}

/// One day's plans: its heading, then each plan with its time and a bar in
/// sage (confirmed) or dashed clay (tentative).
private struct DaySection: View {
    let day: Date
    let plans: [PlanNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.headline).foregroundStyle(.ink)
                Text(day, format: .dateTime.month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(.inkFaint)
            }
            VStack(spacing: 8) {
                ForEach(plans) { plan in
                    PlanRow(plan: plan)
                }
            }
        }
    }

    private var title: String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide))
    }
}

/// A plan in the agenda.
private struct PlanRow: View {
    let plan: PlanNode

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if plan.detail.allDay {
                    Text("All day")
                } else if let start = plan.occurredAt {
                    Text(start, format: .dateTime.hour().minute())
                }
            }
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(.inkMuted)
            .lineLimit(1)
            .fixedSize()
            .frame(width: 66, alignment: .trailing)
            .padding(.top, 2)
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(plan.detail.status == .confirmed ? Color.sage : .clay, style: StrokeStyle(lineWidth: 4, dash: plan.detail.status == .confirmed ? [] : [5, 4]))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.ink)
                if let end = plan.detail.endAt, !plan.detail.allDay {
                    Text("until \(end.formatted(.dateTime.hour().minute()))")
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                }
                if let agent = plan.agentId {
                    Text(Agent.displayName(agent))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Agent.hue(agent))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Agent.hue(agent).opacity(0.12), in: .capsule)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.boneRaised.opacity(0.75), in: .rect(cornerRadius: 18, style: .continuous))
    }
}

/// Add to the timeline in plain words; Yaad reads them into plans.
private struct QuickAdd: View {
    let yaad: YaadClient
    let added: () -> Void

    @State private var text = ""
    @State private var working = false
    @State private var problem: String?
    @State private var done = 0
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add to the timeline")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.ink)
            Text("Say it how you'd say it: \u{201C}Dentist next Thursday at 3:30\u{201D}.")
                .font(.callout)
                .foregroundStyle(.inkMuted)
            TextField("What's happening?", text: $text, axis: .vertical)
                .lineLimit(2...5)
                .focused($focused)
                .padding(14)
                .background(.boneRaised, in: .rect(cornerRadius: 16))
                .disabled(working)
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
            }
            Button {
                add()
            } label: {
                HStack {
                    if working { ProgressView().tint(.bone) }
                    Text(working ? "Yaad is reading it…" : "Add").font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
        }
        .padding(24)
        .sensoryFeedback(.success, trigger: done)
        .onAppear { focused = true }
    }

    private func add() {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        working = true
        problem = nil
        Task {
            defer { working = false }
            do {
                _ = try await yaad.ingest(words)
                done += 1
                added()
                dismiss()
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
