#if os(macOS)
import SwiftUI

/// The Mac's Home: the sidebar with the tiles, Talk to Dadi, every page and
/// every agent thread beside the open page, on the field. The Go menu reaches
/// each page from the keyboard.
struct MacHome: View {
    let services: Services
    let nodeName: String?
    let wordmark: Namespace.ID
    let store: HomeStore
    @Binding var page: HomeView.Page

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<HomeView.Page?>(get: { page }, set: { next in if let next { withAnimation(Motion.settle) { page = next } } })) {
                Label("Home", systemImage: "square.grid.2x2")
                    .tag(HomeView.Page.home)
                Label("Talk to Dadi", systemImage: "sparkles")
                    .font(.body.weight(.semibold))
                    .tag(HomeView.Page.dadi)
                Label("Agents", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(HomeView.Page.agents)
                Label("Memory", systemImage: "brain")
                    .tag(HomeView.Page.memory)
                Label("Timeline", systemImage: "calendar")
                    .tag(HomeView.Page.timeline)
                Label("Ghar", systemImage: "house")
                    .tag(HomeView.Page.ghar)
                Label("Chaavi", systemImage: "key")
                    .tag(HomeView.Page.chaavi)
                Label("System", systemImage: "server.rack")
                    .tag(HomeView.Page.system)
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
                case .home:
                    TileHome(services: services, running: store.running) { next in withAnimation(Motion.settle) { page = next } }
                        .transition(.opacity)
                case .agents:
                    AgentsPage(hath: services.hath, running: store.running) { agentId in withAnimation(Motion.settle) { page = .thread(agentId) } }
                        .transition(.opacity)
                case .memory:
                    MemoryPage(yaad: services.yaad)
                        .transition(.opacity)
                case .dadi:
                    DadiView(hath: services.hath, wordmark: wordmark) { agentId in withAnimation(Motion.settle) { page = .thread(agentId) } }
                case .thread(let agentId):
                    ThreadView(hath: services.hath, agentId: agentId, name: store.name(of: agentId), live: store.live, running: store.running.contains(agentId))
                        .id(agentId)
                        .transition(.opacity)
                case .timeline:
                    TimelinePage(yaad: services.yaad)
                        .transition(.opacity)
                case .ghar:
                    GharPage(ghar: services.ghar)
                        .transition(.opacity)
                case .chaavi:
                    ChaaviPage(chaavi: services.chaavi)
                        .transition(.opacity)
                case .system:
                    SystemPage(nas: services.nas)
                        .transition(.opacity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button { withAnimation(Motion.settle) { page = .dadi } } label: {
                        Text("દાદી").font(.wordmark(20)).foregroundStyle(.sageDeep).inkCentered(.word, size: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Talk to Dadi")
                }
            }
        }
        .focusedSceneValue(\.page, $page)
    }
}

extension FocusedValues {
    /// The page the focused window shows, for the Go menu.
    @Entry var page: Binding<HomeView.Page>?
}

/// The Go menu: every page from the keyboard, and New Conversation for Talk to Dadi.
struct GoCommands: Commands {
    @FocusedValue(\.page) private var page

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            go("New Conversation", .dadi, key: "n")
        }
        CommandMenu("Go") {
            go("Home", .home, key: "0")
            Divider()
            go("Agents", .agents, key: "1")
            go("Memory", .memory, key: "2")
            go("Timeline", .timeline, key: "3")
            go("Ghar", .ghar, key: "4")
            go("Chaavi", .chaavi, key: "5")
            go("System", .system, key: "6")
        }
    }

    private func go(_ title: String, _ target: HomeView.Page, key: KeyEquivalent) -> some View {
        Button(title) { withAnimation(Motion.settle) { page?.wrappedValue = target } }
            .keyboardShortcut(key)
            .disabled(page == nil)
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
