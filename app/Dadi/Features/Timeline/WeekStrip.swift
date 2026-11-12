import SwiftUI

/// The days of one week as a strip to tap, one week to a page: swiping it pages through the weeks
/// with a snap and the selected weekday carries over, so the day below follows. Today wears a ring
/// so it is findable from any week; the shown day is filled and a dot sits under each day with
/// something due.
struct WeekStrip: View {
    /// The day shown below the strip.
    let day: Date
    /// The start of each day with something due, for the dots.
    let dueDays: Set<Date>
    /// Shows `date` below the strip.
    let select: (Date) -> Void

    /// The week the strip has paged to, by its Monday.
    @State private var week: Date?

    /// How many weeks either side of this one the strip reaches.
    nonisolated static let reach = 104

    init(day: Date, dueDays: Set<Date>, select: @escaping (Date) -> Void) {
        self.day = day
        self.dueDays = dueDays
        self.select = select
        _week = State(initialValue: PlannerDay.monday(of: day))
    }

    /// The Monday of every week the strip reaches, around the week holding `now`.
    nonisolated static func weeks(around now: Date, calendar: Calendar = .current) -> [Date] {
        let current = PlannerDay.monday(of: now, calendar: calendar)
        return (-reach...reach).compactMap { calendar.date(byAdding: .day, value: 7 * $0, to: current) }
    }

    /// The day of `week` that falls on the same weekday as `day`.
    nonisolated static func day(in week: Date, keeping day: Date, calendar: Calendar = .current) -> Date? {
        let offset = calendar.dateComponents([.day], from: PlannerDay.monday(of: day, calendar: calendar), to: calendar.startOfDay(for: day)).day ?? 0
        return calendar.date(byAdding: .day, value: offset, to: week)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Self.weeks(around: .now), id: \.self) { monday in
                    page(of: monday)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $week)
        .frame(height: 62)
        .onChange(of: week) { _, paged in
            guard let paged, paged != PlannerDay.monday(of: day), let next = Self.day(in: paged, keeping: day) else { return }
            select(next)
        }
        .onChange(of: day) { _, shown in
            let monday = PlannerDay.monday(of: shown)
            if week != monday { withAnimation(Motion.settle) { week = monday } }
        }
        .sensoryFeedback(.selection, trigger: week)
    }

    private func page(of monday: Date) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                if let date = Calendar.current.date(byAdding: .day, value: offset, to: monday) {
                    cell(date)
                }
            }
        }
    }

    private func cell(_ date: Date) -> some View {
        let shown = Calendar.current.isDate(date, inSameDayAs: day)
        let today = Calendar.current.isDateInToday(date)
        return Button { select(date) } label: {
            VStack(spacing: 3) {
                Text(date, format: .dateTime.weekday(.narrow))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(shown ? Color.bone.opacity(0.8) : .inkFaint)
                Text(date, format: .dateTime.day())
                    .font(.callout.weight(shown || today ? .bold : .medium).monospacedDigit())
                    .foregroundStyle(shown ? Color.bone : today ? .sageDeep : .ink)
                Circle()
                    .fill(shown ? Color.bone : .clay)
                    .frame(width: 4, height: 4)
                    .opacity(dueDays.contains(Calendar.current.startOfDay(for: date)) ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if shown {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.sageDeep)
                } else if today {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.sageDeep.opacity(0.55), lineWidth: 1.5)
                }
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel((today ? "Today, " : "") + date.formatted(.dateTime.weekday(.wide).month().day()))
        .accessibilityAddTraits(shown ? .isSelected : [])
    }
}
