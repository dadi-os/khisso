import SwiftUI

/// Talk to Dadi: your words go to the router, which sends them on as you to the
/// agent that owns them. While it works this is a waiting room; when it is
/// done the first agent's thread opens and the words are gone from here.
struct DadiView: View {
    let hath: HathClient
    /// Opens the thread of the agent the router handed off to.
    let open: (String) -> Void

    @State private var draft = ""
    @State private var handingOff: String?
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("દાદી")
                .font(.system(size: handingOff == nil ? 60 : 42, weight: .medium))
                .foregroundStyle(.tint)
                .animation(.smooth, value: handingOff)
            if let words = handingOff {
                Text(words)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.tint.opacity(0.14), in: .rect(cornerRadius: 18))
                    .frame(maxWidth: 420)
                Label("Finding the right agent", systemImage: "arrow.triangle.branch")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse)
            } else {
                Text("Tell Dadi what you need. It lands with the agent who owns it, and that chat opens.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Spacer()
            Composer(text: $draft, placeholder: "Message Dadi…", busy: handingOff != nil, send: handOff)
        }
        .padding()
        .navigationTitle("Dadi")
    }

    private func handOff() {
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        draft = ""
        problem = nil
        handingOff = words
        Task {
            do {
                let response = try await hath.route(words)
                handingOff = nil
                guard let first = response.messages.first else {
                    problem = "Dadi didn't send this anywhere."
                    return
                }
                open(first.toAgentId)
            } catch {
                handingOff = nil
                draft = words
                problem = error.localizedDescription
            }
        }
    }
}
