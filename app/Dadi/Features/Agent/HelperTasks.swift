import SwiftUI

/// The agent's helper tasks, a row each as on System; tapping one opens its card, where it is paused,
/// resumed or stopped.
struct HelperTasks: View {
    let hath: HathClient
    let nas: NasClient
    /// The owning agent's name.
    let owner: String
    /// The agent's helper tasks, most recently active first.
    let tasks: [NasTask]
    /// Reads the tasks again, after one was stopped or changed.
    let changed: () async -> Void

    private var active: Int { tasks.filter(\.stoppable).count }

    var body: some View {
        InsetCard(title: "Helper tasks", count: active > 0 ? "\(active) active" : nil) {
            VStack(spacing: 0) {
                ForEach(tasks) { task in
                    TaskRow(hath: hath, nas: nas, task: task, owner: owner, changed: changed)
                    if task.id != tasks.last?.id { Rectangle().fill(.rule).frame(height: 1) }
                }
            }
        }
    }
}
