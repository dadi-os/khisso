import SwiftUI

/// The notice a Planner view shows over content it already has: dadi out of reach (the last answer, and when), or
/// Yaad failing to answer a refresh.
struct FeedBanner: View {
    /// False while dadi is out of reach.
    let online: Bool
    /// Why the last read failed, when it did.
    let error: String?
    /// When the shown data last arrived.
    let readAt: Date?

    var body: some View {
        if let error {
            if online { ModuleBanner(module: "Yaad", why: error) } else if let readAt { StaleBanner(since: readAt) }
        } else if !online, let readAt {
            StaleBanner(since: readAt)
        }
    }
}

/// What makes the Week or Month read again: another period, a change in Yaad, or a retry.
struct PeriodReload: Hashable {
    let start: Date
    let change: Int
    let retry: Int
}

/// Day's loading shape: hour lines with three plan blocks.
struct DayTimelineSkeleton: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle().fill(Color.rule).frame(height: 1).padding(.leading, 60)
                    Spacer(minLength: 0)
                }
            }
            SkeletonBar(radius: 12).frame(height: 52).padding(.leading, 64).offset(y: 46)
            SkeletonBar(radius: 12).frame(height: 84).padding(.leading, 64).offset(y: 140)
            SkeletonBar(radius: 12).frame(height: 40).padding(.leading, 64).offset(y: 270)
        }
        .frame(height: 380)
        .accessibilityLabel("Loading")
    }
}

/// The Checklist's loading shape: four task rows.
struct ChecklistSkeleton: View {
    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 12) {
                    SkeletonBar(radius: 11).frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBar(radius: 5).frame(height: 12)
                        SkeletonBar(radius: 5).frame(width: 120, height: 9)
                    }
                }
            }
        }
        .accessibilityLabel("Loading")
    }
}

/// Week's loading shape: a day header row over seven columns with a few plan bars.
struct WeekSkeleton: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in SkeletonBar(radius: 8).frame(height: 36) }
            }
            HStack(alignment: .top, spacing: 6) {
                ForEach(0..<3, id: \.self) { column in
                    VStack(spacing: 8) {
                        SkeletonBar(radius: 9).frame(height: 44)
                        SkeletonBar(radius: 9).frame(height: 70)
                        SkeletonBar(radius: 9).frame(height: column == 1 ? 90 : 48)
                    }
                }
            }
        }
        .accessibilityLabel("Loading")
    }
}

/// Month's loading shape: the grid of tiles.
struct MonthSkeleton: View {
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(0..<35, id: \.self) { _ in SkeletonBar(radius: 10).frame(height: 96) }
        }
        .accessibilityLabel("Loading")
    }
}
