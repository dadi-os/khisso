import SwiftUI

/// The Stop control's state: the call in flight, what Hath answered, and why it failed.
struct StopState: Equatable {
    var pending = false
    /// Hath's answer to the last stop of this agent; its `haltFailed` is never hidden.
    var result: StopResult?
    var error: String?
}

/// The line that eases open under the action rail: what Stop does, Stop and Keep going; and, once it ran, what Hath
/// could not halt.
struct StopConfirm: View {
    let stop: StopState
    @Binding var confirming: Bool
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if confirming {
                HStack(spacing: 8) {
                    Text("Ends the run and its helper tasks.").font(.system(size: 13)).foregroundStyle(.inkMuted)
                    Spacer(minLength: 4)
                    Button("Stop", role: .destructive) {
                        confirming = false
                        onStop()
                    }
                    .buttonStyle(.bordered)
                    .disabled(stop.pending)
                    Button("Keep going") { confirming = false }
                        .buttonStyle(.plain)
                        .foregroundStyle(.inkMuted)
                        .frame(minHeight: 44)
                }
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.sage.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
            if let result = stop.result {
                ForEach(result.haltFailed, id: \.task) { failed in
                    Text("Could not halt \(failed.task.replacingOccurrences(of: "task/", with: "")): \(failed.error)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.danger)
                        .textSelection(.enabled)
                }
            }
            if let error = stop.error {
                Text(error).font(.system(size: 12.5)).foregroundStyle(.danger).textSelection(.enabled)
            }
        }
        .animation(Motion.snap, value: confirming)
    }
}
