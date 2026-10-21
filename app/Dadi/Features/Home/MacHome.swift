#if os(macOS)
import SwiftUI

/// The Mac's Home: the sidebar with Talk to Dadi and every agent thread beside
/// the open page, on the field.
struct MacHome: View {
    let hath: HathClient
    let nodeName: String?
    let wordmark: Namespace.ID
    let store: HomeStore
    @Binding var page: HomeView.Page

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<HomeView.Page?>(get: { page }, set: { next in if let next { withAnimation(Motion.settle) { page = next } } })) {
                Label("Talk to Dadi", systemImage: "sparkles")
                    .font(.body.weight(.semibold))
                    .tag(HomeView.Page.dadi)
                Section("Agents") {
                    ForEach(store.threads) { thread in
                        ThreadRow(thread: thread, running: store.running.contains(thread.agentId), selected: false)
                            .padding(.vertical, 3)
                            .tag(HomeView.Page.thread(thread.agentId))
                    }
                }
                if let error = store.liveError {
                    Label(error, systemImage: "bolt.horizontal.circle").foregroundStyle(.clay)
                }
                if let error = store.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.danger)
                }
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 420)
            .safeAreaInset(edge: .bottom) {
                if let nodeName {
                    Label(nodeName, systemImage: "circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.inkMuted)
                        .labelStyle(DotLabelStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
        } detail: {
            ZStack {
                FieldBloom()
                switch page {
                case .dadi:
                    DadiView(hath: hath, wordmark: wordmark) { agentId in withAnimation(Motion.settle) { page = .thread(agentId) } }
                case .thread(let agentId):
                    ThreadView(hath: hath, agentId: agentId, name: store.name(of: agentId), live: store.live, running: store.running.contains(agentId))
                        .id(agentId)
                        .transition(.opacity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button { withAnimation(Motion.settle) { page = .dadi } } label: {
                        Text("દાદી").font(.wordmark(20)).foregroundStyle(.sageDeep)
                    }
                    .buttonStyle(.plain)
                    .help("Talk to Dadi")
                }
            }
        }
    }
}

/// A label whose icon is a small sage dot, for "online as" captions.
private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Circle().fill(.sage).frame(width: 7, height: 7)
            configuration.title
        }
    }
}
#endif
