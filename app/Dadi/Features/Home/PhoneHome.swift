import SwiftUI

/// The iPhone's Home: dadi's five pages in the dock, one at a time on the
/// field, with the drawer lying underneath. The dock is the system tab bar,
/// liquid glass that shrinks while a page scrolls down; each page keeps its
/// own place while another is open, and Dadi keeps the thread that was open.
/// Swipe from the left edge or tap the menu button and the whole page, dock
/// and all, slides right to uncover the drawer, following the finger and
/// springing open or closed by where and how fast it was let go. Opening it
/// puts the keyboard away; a swipe left anywhere on the page, or a tap on it,
/// closes it. Pages run the full height of the screen: their content scrolls
/// up under the floating menu button, the page's name in its glass bubble
/// and the page's action, on past the Dynamic Island.
struct PhoneHome: View {
    let services: Services
    let wordmark: Namespace.ID
    let store: HomeStore
    @Binding var page: HomeView.Page

    @State private var open = false
    @State private var drag: CGFloat = 0
    @State private var opened = 0
    /// What the Dadi tab shows: Talk to Dadi or a thread, kept while another
    /// tab is open.
    @State private var dadiPage: HomeView.Page = .dadi
    /// False until Home has settled in from Connecting, so the bar fades in
    /// around the wordmark instead of arriving with it.
    @State private var arrived = false
    /// True while a sideways drag is moving the drawer and just after, so the
    /// row a swipe ends on is not taken as a tap.
    @State private var swiping = false
    /// The agent whose sheet is up.
    @State private var agentSheet: String?
    /// The Timeline's view, set from its name bubble or its drawer.
    @State private var timelineMode = TimelineMode.day
    @State private var dadiIcon = DadiGlyph.render()

    /// The strip along the left edge that opens the drawer. It sits over the
    /// page, so a swipe that starts in it always pulls the drawer instead of
    /// moving the page, as the Timeline's day swipe would.
    private let edge: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width * 0.84, 340)
            let shift = max(0, min(width, (open ? width : 0) + drag))
            let progress = shift / width
            ZStack(alignment: .leading) {
                FieldBloom()
                Drawer {
                    switch page.tab {
                    case .timeline:
                        TimelineDrawer(yaad: services.yaad, mode: timelineMode) { mode in
                            guard !swiping else { return }
                            withAnimation(Motion.settle) { timelineMode = mode }
                            set(open: false)
                        } tellDadi: {
                            choose(.dadi)
                        }
                    default:
                        AgentsDrawer(store: store, page: page) { next in
                            guard !swiping else { return }
                            choose(next)
                        } details: { agentId in
                            set(open: false)
                            agentSheet = agentId
                        }
                    }
                }
                    .frame(width: width)
                    .opacity(progress > 0 ? 1 : 0)
                dock
                    .overlay {
                        Color.black.opacity(0.18 * progress)
                            .ignoresSafeArea()
                            .allowsHitTesting(open)
                            .onTapGesture { set(open: false) }
                    }
                    .overlay(alignment: .leading) {
                        if !open {
                            Color.clear
                                .frame(width: edge)
                                .contentShape(.rect)
                                .ignoresSafeArea()
                                .gesture(drawerDrag(width: width))
                        }
                    }
                    .clipShape(.rect(cornerRadius: 44 * min(1, progress * 4), style: .continuous))
                    .shadow(color: .black.opacity(0.14 * progress), radius: 18, x: -4)
                    .offset(x: shift)
                    .ignoresSafeArea()
            }
            .gesture(open ? drawerDrag(width: width) : nil)
        }
        .sheet(isPresented: Binding { agentSheet != nil } set: { if !$0 { agentSheet = nil } }) {
            if let agentId = agentSheet {
                AgentSheet(services: services, agentId: agentId, name: store.name(of: agentId), lanes: store.lanes(of: agentId), connections: store.connections, nameOf: store.name(of:))
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.boneRaised)
            }
        }
        .sensoryFeedback(.selection, trigger: opened)
        .sensoryFeedback(.selection, trigger: page.tab)
        .onAppear { withAnimation(Motion.settle.delay(0.35)) { arrived = true } }
        .onChange(of: page, initial: true) {
            if page.tab == .dadi { dadiPage = page }
        }
    }

    /// The five pages in the system tab bar.
    private var dock: some View {
        TabView(selection: tabSelection) {
            Tab(value: HomeView.Tab.dadi) {
                chrome(dadiContent, tab: .dadi)
            } label: {
                Label { Text("Dadi") } icon: { Image(uiImage: dadiIcon) }
            }
            Tab("Timeline", systemImage: "calendar", value: HomeView.Tab.timeline) {
                chrome(
                    TimelinePage(yaad: services.yaad, mode: $timelineMode) { agentId in
                        show(.thread(agentId))
                    } tellDadi: {
                        show(.dadi)
                    },
                    tab: .timeline
                )
            }
            Tab("Ghar", systemImage: "house", value: HomeView.Tab.ghar) {
                chrome(GharPage(ghar: services.ghar), tab: .ghar)
            }
            Tab("Chaavi", systemImage: "key.horizontal", value: HomeView.Tab.chaavi) {
                chrome(ChaaviPage(chaavi: services.chaavi), tab: .chaavi)
            }
            Tab("System", systemImage: "server.rack", value: HomeView.Tab.system) {
                chrome(SystemPage(nas: services.nas), tab: .system)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.sageDeep)
    }

    /// Talk to Dadi, or the thread the Dadi tab has open.
    private var dadiContent: some View {
        ZStack {
            switch dadiPage {
            case .thread(let agentId):
                ThreadView(hath: services.hath, agentId: agentId, name: store.name(of: agentId), live: store.live, lanes: store.lanes(of: agentId), connections: store.connections) { seq in
                    Task { await store.markRead(services.hath, agentId: agentId, through: seq) }
                } details: {
                    agentSheet = agentId
                }
                    .id(agentId)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            default:
                DadiView(hath: services.hath, threads: store.threads, lanes: store.lanes(of:), name: store.name(of:), wordmark: wordmark) { agentId in
                    show(.thread(agentId))
                } details: { agentId in
                    agentSheet = agentId
                } openDrawer: {
                    set(open: true)
                }
                .transition(.opacity)
            }
        }
    }

    /// A page on the field under its floating bar, running the full height
    /// of the screen.
    private func chrome(_ content: some View, tab: HomeView.Tab) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { FieldBloom() }
            .scrollEdgeEffectHidden(true, for: .top)
            .safeAreaBar(edge: .top) { topBar(tab) }
    }

    private func topBar(_ tab: HomeView.Tab) -> some View {
        let shown = tab == .dadi ? dadiPage : tab.home
        return HStack {
            Button { set(open: !open) } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Open sidebar")
            Spacer()
            if tab == .timeline {
                Menu {
                    Picker("View", selection: $timelineMode.animation(Motion.settle)) {
                        ForEach(TimelineMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                        }
                    }
                } label: {
                    NameBubble(title: timelineMode.rawValue, accessory: "chevron.down")
                        .contentTransition(.opacity)
                }
                .accessibilityLabel("Timeline view: \(timelineMode.rawValue)")
                .sensoryFeedback(.selection, trigger: timelineMode)
            } else if let title = title(of: shown) {
                NameBubble(title: title, details: shown.isThread ? { if case .thread(let agentId) = shown { agentSheet = agentId } } : nil)
                    .id(title)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
            Spacer()
            Button { show(.dadi) } label: {
                Image(systemName: "square.and.pencil")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .opacity(shown == .dadi ? 0 : 1)
            .disabled(shown == .dadi)
            .accessibilityLabel("Talk to Dadi")
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .opacity(arrived ? 1 : 0)
        .animation(Motion.snap, value: shown)
    }

    /// The page's name for its bubble; Talk to Dadi has none.
    private func title(of page: HomeView.Page) -> String? {
        switch page {
        case .dadi: nil
        case .thread(let agentId): store.name(of: agentId)
        case .timeline: "Timeline"
        case .ghar: "Ghar"
        case .chaavi: "Chaavi"
        case .system: "System"
        }
    }

    /// The dock's selection: choosing Dadi goes back to the thread it had open.
    private var tabSelection: Binding<HomeView.Tab> {
        Binding {
            page.tab
        } set: { next in
            guard next != page.tab else { return }
            dismissKeyboard()
            page = next == .dadi ? dadiPage : next.home
        }
    }

    /// Opens `next`, in its own tab.
    private func show(_ next: HomeView.Page) {
        withAnimation(Motion.settle) {
            if next.tab == .dadi { dadiPage = next }
            page = next
        }
    }

    /// Shows `next` and closes the drawer.
    private func choose(_ next: HomeView.Page) {
        show(next)
        set(open: false)
    }

    private func set(open next: Bool) {
        if next { dismissKeyboard() }
        if next != open { opened += 1 }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            open = next
            drag = 0
        }
    }

    /// Follows the finger from the left edge (or anywhere while open) and
    /// settles by the predicted end, so a flick opens or closes it.
    private func drawerDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if !open && drag == 0 { dismissKeyboard() }
                swiping = true
                drag = value.translation.width
            }
            .onEnded { value in
                let end = (open ? width : 0) + value.predictedEndTranslation.width
                set(open: end > width / 2)
                Task {
                    do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                    swiping = false
                }
            }
    }
}

/// The Dadi tab's icon: દ, the wordmark's first letter, drawn as a template
/// image, since a tab's icon has to be an image.
private enum DadiGlyph {
    /// The icon's side in points, a system tab icon's size.
    static let side: CGFloat = 28

    @MainActor
    static func render() -> UIImage {
        let renderer = ImageRenderer(content: Text("દ")
            .font(.wordmark(25, weight: .semibold))
            .inkCentered(.letter, size: 25)
            .frame(width: side, height: side))
        renderer.scale = 3
        return renderer.uiImage!.withRenderingMode(.alwaysTemplate)
    }
}

/// Puts the keyboard away, whichever field has it.
@MainActor
private func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// The drawer's sheet: the wordmark over the page's own drawer content, on a
/// frosted sheet that runs to every edge of the screen.
private struct Drawer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("દાદી")
                    .font(.wordmark(34))
                    .inkCentered(.word, size: 34)
                    .foregroundStyle(.sageDeep)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                content
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            Rectangle()
                .fill(.thinMaterial)
                .overlay(Color.bone.opacity(0.35))
                .ignoresSafeArea()
        }
    }
}

/// A page's name in a glass bubble, as thaali's pane header.
struct NameBubble: View {
    let title: String
    /// Opens the page's details when the name is tapped; nil for a page with none.
    var details: (() -> Void)?
    /// The symbol after the name: a chevron right when it opens details, or
    /// the caller's, as a menu's chevron down.
    var accessory: String?

    var body: some View {
        let symbol = accessory ?? (details == nil ? nil : "chevron.right")
        let label = HStack(spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.ink)
                .lineLimit(1)
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.inkFaint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(symbol == nil ? .regular : .regular.interactive(), in: .capsule)
        if let details {
            Button(action: details) { label }
                .buttonStyle(.plain)
                .accessibilityHint("Shows details and activity")
        } else {
            label
        }
    }
}
