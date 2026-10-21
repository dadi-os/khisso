import SwiftUI

/// The box: healthy, or which of its modules are down, and how fresh that is.
struct BoxPage: View {
    let store: WatchStore

    var body: some View {
        VStack(spacing: 8) {
            if let box = store.snapshot?.box {
                Image(systemName: box.down.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(box.down.isEmpty ? Color.sage : .danger)
                    .symbolEffect(.bounce, value: box.down.isEmpty)
                Text(box.down.isEmpty ? "dadi is healthy" : "\(box.down.map { $0.capitalized }.joined(separator: ", ")) down")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "server.rack").font(.system(size: 34)).foregroundStyle(.secondary)
                Text("Open dadi on your iPhone.").font(.footnote).foregroundStyle(.secondary)
            }
            if let at = store.snapshot?.at {
                Text("Updated \(at.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !store.reachable {
                Label("iPhone not nearby", systemImage: "iphone.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let problem = store.problem {
                Text(problem).font(.caption2).foregroundStyle(.danger).multilineTextAlignment(.center)
            }
        }
    }
}
