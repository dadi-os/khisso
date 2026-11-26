import SwiftUI

/// What the agent is doing and has done: the current call (the latest call while a wake runs) over
/// the wake timeline, newest first, a page at a time. The running or latest wake is open until another is
/// chosen; one wake is open at a time. It reads again when Hath's event stream reconnects or reports a
/// wake changing.
struct WakeTimeline: View {
    let hath: HathClient
    let agentId: String
    let nameOf: (String) -> String
    /// Opens the sheet of an agent a wake names.
    let selectAgent: (String) -> Void
    /// Changes when the wakes must be read again.
    let refresh: Refresh
    /// The agent's routines and reminders, to name the wake one fired.
    let routines: Routines?

    /// What makes the timeline read again.
    struct Refresh: Hashable {
        /// The Home event stream's connection count.
        let connections: Int
        /// Wake events seen for this agent.
        let wakeChanges: Int
    }

    /// Wakes one page reads.
    static let pageSize = 20

    @State private var wakes: [WakeSummary]?
    @State private var nextBefore: WakeCursor?
    @State private var loadingMore = false
    @State private var error: String?
    /// When the wakes last arrived, for the banner a failed refresh leaves.
    @State private var readAt = Date.now
    @State private var details: [String: WakeDetail] = [:]
    @State private var detailErrors: [String: String] = [:]
    /// The wake Ankur opened, or nil for the one that opens itself; `.some(nil)` is none open.
    @State private var chosen: String??

    private var latest: WakeSummary? { wakes?.first }
    private var runningId: String? { latest?.outcome == .running ? latest?.id : nil }
    private var openId: String? { chosen ?? latest?.id }
    private var currentCall: CurrentCall? { runningId.flatMap { details[$0] }.flatMap { WakeFormat.currentCall($0.entries) } }

    var body: some View {
        InsetCard(title: "Wakes") {
            if let currentCall { callFact(currentCall) }
            list
        }
        .task(id: refresh) {
            await loadFirst()
            let held = openId.flatMap { details[$0] == nil ? nil : $0 }
            await loadDetails(Set([runningId, held].compactMap { $0 }))
        }
        .task(id: openId) {
            if let openId, details[openId] == nil { await loadDetails([openId]) }
        }
    }

    @ViewBuilder
    private var list: some View {
        if let wakes {
            if error != nil { StaleBanner(since: readAt) }
            if wakes.isEmpty {
                EmptyState(title: "No wakes yet", detail: "Its activity shows here once it wakes.").padding(.vertical, 12)
            } else {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(wakes) { wake in
                            WakeRow(
                                hath: hath, wake: wake, open: openId == wake.id, detail: details[wake.id], detailError: detailErrors[wake.id],
                                routines: routines, nameOf: nameOf, now: context.date,
                                toggle: { chosen = .some(openId == wake.id ? nil : wake.id) }, selectAgent: selectAgent,
                                retry: { Task { await loadDetails([wake.id]) } }
                            )
                        }
                        if nextBefore != nil {
                            Button { Task { await loadMore() } } label: {
                                Text(loadingMore ? "Loading…" : "Load earlier").font(.footnote.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .foregroundStyle(.sageDeep)
                            .disabled(loadingMore)
                        }
                    }
                }
            }
        } else if let error {
            ErrorCard(service: "Hath", status: nil, message: "Could not read the wakes: \(error)") { Task { await loadFirst() } }
        } else {
            SkeletonRows(count: 3, height: 56)
        }
    }

    private func callFact(_ call: CurrentCall) -> some View {
        FactRow(label: "Current call", hint: "\(call.running ? "running " : "")\(call.at.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))", wrap: true) {
            Text(call.target.isEmpty ? call.name : "\(call.name) \(call.target)")
        }
    }

    /// Reads the newest page, keeping the older wakes already loaded below it.
    private func loadFirst() async {
        do {
            let page = try await hath.wakes(agentId: agentId, limit: Self.pageSize)
            if wakes == nil { nextBefore = page.nextBefore }
            wakes = Self.merged(wakes ?? [], with: page.wakes)
            error = nil
            readAt = .now
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let cursor = nextBefore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await hath.wakes(agentId: agentId, limit: Self.pageSize, before: cursor)
            wakes = (wakes ?? []) + page.wakes.filter { wake in !(wakes ?? []).contains { $0.id == wake.id } }
            nextBefore = page.nextBefore
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadDetails(_ ids: Set<String>) async {
        for id in ids {
            do {
                details[id] = try await hath.wake(agentId: agentId, wakeId: id)
                detailErrors[id] = nil
            } catch is CancellationError {
                return
            } catch {
                detailErrors[id] = error.localizedDescription
            }
        }
    }

    /// The newest page `fresh` over the wakes already `held`: every fresh wake, then each held one older than the oldest fresh wake.
    nonisolated static func merged(_ held: [WakeSummary], with fresh: [WakeSummary]) -> [WakeSummary] {
        guard let oldest = fresh.last else { return held }
        return fresh + held.filter { $0.startedAt < oldest.startedAt }
    }
}
