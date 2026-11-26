import SwiftUI

/// A compact month for jumping to a date: whole weeks from Monday with the neighbouring months' days dimmed, today
/// ringed, the chosen day filled and a small dot under each day that has plans. A tap on any day picks it.
struct MiniCalendar: View {
    /// The first day of the month shown.
    @Binding var month: Date
    /// The days (local midnight) that have plans.
    let marked: Set<Date>
    /// The day the Planner shows now, when it shows one.
    let selected: Date?
    /// Picks `day`.
    let pick: (Date) -> Void

    /// The height of a day's cell.
    static let cell: CGFloat = 40

    /// The days (local midnight) among `days` that hold a plan Ankur has not declined.
    static func marks(_ plans: [Plan], days: [Date], calendar: Calendar = .current) -> Set<Date> {
        let kept = plans.filter { !$0.declined }
        return Set(days.map { calendar.startOfDay(for: $0) }.filter { day in kept.contains { PlanFilter.overlaps($0, day: day, calendar: calendar) } })
    }

    var body: some View {
        let days = PlannerLayout.monthGrid(month)
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(month, format: .dateTime.month(.wide).year())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ink)
                    .contentTransition(.opacity)
                Spacer()
                step("chevron.left", label: "Previous month", by: -1)
                step("chevron.right", label: "Next month", by: 1)
            }
            HStack(spacing: 0) {
                ForEach(Array(days.prefix(7)), id: \.self) { day in
                    Text(day, format: .dateTime.weekday(.narrow)).font(.caption2.weight(.semibold)).foregroundStyle(.inkFaint).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(days, id: \.self) { day in cellView(day) }
            }
        }
        .animation(Motion.snap, value: month)
    }

    private func step(_ symbol: String, label: String, by months: Int) -> some View {
        Button {
            if let next = Calendar.current.date(byAdding: .month, value: months, to: month) { month = next }
        } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.inkMuted).frame(width: 44, height: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func cellView(_ day: Date) -> some View {
        let calendar = Calendar.current
        let chosen = selected.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let today = calendar.isDateInToday(day)
        let focused = MonthPaging.isFocused(day, in: month)
        return Button { pick(day) } label: {
            VStack(spacing: 3) {
                Text(day, format: .dateTime.day())
                    .font(.system(size: 14, weight: chosen || today ? .bold : .medium).monospacedDigit())
                    .foregroundStyle(chosen ? Color.bone : today ? .sageDeep : .ink)
                    .frame(width: 30, height: 30)
                    .background {
                        if chosen {
                            Circle().fill(Color.sageDeep)
                        } else if today {
                            Circle().strokeBorder(Color.sageDeep.opacity(0.55), lineWidth: 1.5)
                        }
                    }
                Circle().fill(marked.contains(calendar.startOfDay(for: day)) ? Color.sage : .clear).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: Self.cell + 4)
            .opacity(focused ? 1 : 0.38)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel((today ? "Today, " : "") + day.formatted(.dateTime.weekday(.wide).month().day()) + (marked.contains(calendar.startOfDay(for: day)) ? ", has plans" : ""))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
