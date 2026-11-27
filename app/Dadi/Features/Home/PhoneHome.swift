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
/// and the page's action, on past the Dynamic Island, and down under the
/// dock, softening as it goes under either so nothing reads through the glass.
struct PhoneHome: View {
    let services: Services
    let store: HomeStore
    let online: Bool
    @Binding var page: HomeView.Page

    @State private var open = false
    @State private var drag: CGFloat = 0
    @State private var opened = 0
    /// What the Chats tab shows: the list or a thread, kept while another
    /// tab is open.
    @State private var dadiPage: HomeView.Page = .dadi
    /// What the drawer narrowed the chat list to.
    @State private var chatsFilter = ChatGroups.Filter.all
    /// False until Home has settled in from Connecting, so the bar fades in
    /// after Connecting rather than arriving with it.
    @State private var arrived = false
    /// True while a sideways drag is moving the drawer and just after, so the
    /// row a swipe ends on is not taken as a tap.
    @State private var swiping = false
    /// The agent whose sheet is up.
    @State private var agentSheet: String?
    /// The router dock: the draft, the composer over the page and the last send.
    @State private var router = RouterDock()
    /// Each thread's draft, which the dock's accessory writes while its thread is open.
    @State private var drafts = ThreadDrafts()
    /// The toasts over the page.
    @State private var toaster = Toaster()
    /// The dock's re-select of the tab already open.
    @State private var reselect = TabReselect()
    @Namespace private var sheetWordmark
    /// What the Planner shows, set from its name bubble, its drawer, Week and Month, and a re-tap of its tab.
    @State private var planner = PlannerRoute()
    /// Bumped to bring the Planner's Day view to now.
    @State private var plannerScrollNow = 0
    /// Ghar's devices and tags, which its page and its drawer share.
    @State private var ghar: GharStore
    /// What the Ghar page is narrowed to, set from its chips or its drawer.
    @State private var gharFilter = GharPage.Filter.everywhere
    /// Chaavi's vault, which its page and its drawer share.
    @State private var chaavi: ChaaviStore
    /// True while Chaavi's new item sheet is up.
    @State private var creatingItem = false
    /// The box's status, devices and errors, which System's page and drawer share.
    @State private var system: SystemStore
    /// The System section the drawer asked the page to scroll to.
    @State private var systemFocus: SystemPage.Section?

    /// The strip along the left edge that opens the drawer. It sits over the
    /// page, so a swipe that starts in it always pulls the drawer instead of
    /// moving the page, as the Planner's day swipe would.
    private let edge: CGFloat = 36

    init(services: Services, store: HomeStore, online: Bool, page: Binding<HomeView.Page>) {
        self.services = services
        self.store = store
        self.online = online
        _page = page
        _ghar = State(initialValue: GharStore(ghar: services.ghar))
        _chaavi = State(initialValue: ChaaviStore(chaavi: services.chaavi))
        _system = State(initialValue: SystemStore(nas: services.nas))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width * 0.84, 340)
            let shift = max(0, min(width, (open ? width : 0) + drag))
            let progress = shift / width
            ZStack(alignment: .leading) {
                FieldBloom()
                Drawer {
                    switch page.tab {
                    case .ghar:
                        GharDrawer(store: ghar, filter: gharFilter) { next in
                            guard !swiping else { return }
                            withAnimation(Motion.snap) { gharFilter = next }
                            set(open: false)
                        }
                    case .chaavi:
                        ChaaviDrawer(store: chaavi) { kind, scope in
                            guard !swiping else { return }
                            withAnimation(Motion.settle) {
                                chaavi.kind = kind
                                chaavi.scope = scope
                            }
                            set(open: false)
                        }
                    case .system:
                        SystemDrawer(store: system) { section in
                            guard !swiping else { return }
                            systemFocus = section
                            set(open: false)
                        }
                    case .planner:
                        PlannerDrawer(yaad: services.yaad, route: planner, online: online, message: plannerMessage(_:ready:), reachable: store.isActive, nameOf: store.name(of:)) { next in
                            guard !swiping else { return }
                            withAnimation(Motion.settle) { planner = next }
                            set(open: false)
                        }
                    case .dadi:
                        ChatsDrawer(store: store, filter: chatsFilter) {
                            guard !swiping else { return }
                            set(open: false)
                            router.compose()
                        } choose: { next in
                            guard !swiping else { return }
                            withAnimation(Motion.snap) { chatsFilter = next }
                            show(.dadi)
                            set(open: false)
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
                        if !open && !page.isThread {
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
                AgentSheet(services: services, agentId: agentId, name: store.name(of: agentId), agent: store.agents[agentId], counts: store.counts(of: agentId), connections: store.connections, wakeChanges: store.wakeChanges[agentId, default: 0], scheduleChanges: store.scheduleChanges, nameOf: store.name(of:), refreshAgents: { await store.refreshAgents(services.hath) }, selectAgent: { agentSheet = $0 }) {
                    agentSheet = nil
                    show(.thread(agentId))
                }
                    .id(agentId)
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
        .overlay {
            RouterCompose(dock: router, active: store.routing, send: sendToRouter)
        }
        .overlay(alignment: .top) {
            ToastStack(toaster: toaster)
                .padding(.top, 64)
        }
        .sensoryFeedback(.success, trigger: router.handedOff)
        .onChange(of: store.sideProblem) { _, problem in
            guard let problem else { return }
            toaster.show(Toast(key: "side-problem", title: "Chats may be out of date", detail: problem, symbol: "exclamationmark.triangle.fill", failure: true))
        }
        .onChange(of: store.wakeFailure) { _, failure in
            guard let failure else { return }
            let name = store.name(of: failure.agentId)
            toaster.show(Toast(key: "wake-failed-\(failure.agentId)", title: "\(name)'s run failed", detail: "Its activity has the reason.", symbol: "exclamationmark.triangle.fill", failure: true) { agentSheet = failure.agentId })
        }
        .onChange(of: store.routerFailure) { _, failure in
            guard let failure, !router.sending else { return }
            toaster.show(Toast(key: "router-failed", title: "Dadi could not route a message", detail: failure.message, symbol: "exclamationmark.triangle.fill", failure: true))
        }
    }

    /// The five pages in the system tab bar.
    private var dock: some View {
        TabView(selection: tabSelection) {
            Tab(value: HomeView.Tab.dadi) {
                chrome(dadiContent, tab: .dadi)
            } label: {
                Label("Chats", systemImage: "bubble.left.and.bubble.right")
            }
            .badge(chatsBadge)
            Tab("Planner", systemImage: "calendar", value: HomeView.Tab.planner) {
                chrome(
                    PlannerPage(yaad: services.yaad, route: $planner, scrollNow: plannerScrollNow, online: online, message: plannerMessage(_:ready:), reachable: store.isActive, nameOf: store.name(of:)),
                    tab: .planner
                )
            }
            Tab("Ghar", systemImage: "house", value: HomeView.Tab.ghar) {
                chrome(GharPage(store: ghar, filter: $gharFilter), tab: .ghar)
            }
            Tab("Chaavi", systemImage: "key.horizontal", value: HomeView.Tab.chaavi) {
                chrome(ChaaviPage(store: chaavi, creating: $creatingItem), tab: .chaavi)
            }
            Tab("System", systemImage: "server.rack", value: HomeView.Tab.system) {
                chrome(SystemPage(hath: services.hath, store: system, focus: $systemFocus, nameOf: store.name(of:), online: online), tab: .system)
            }
        }
        .tabBarMinimizeBehavior(page.isThread ? .onScrollUp : .onScrollDown)
        .tabViewBottomAccessory(isEnabled: presentation.showsAccessory) {
            DockAccessory(presentation: presentation, router: router, active: store.routing, online: online)
        }
        .tint(.sageDeep)
        .environment(reselect)
        .background { TabReselectProbe(reselected: reselected) }
    }

    /// The dock's re-select, the same for every tab: a page in a sub-state goes back to its root; one already at its
    /// root is left to scroll to the top. The Planner goes back to Timeline on today, and scrolls to now when it is there.
    private func reselected(_ tab: HomeView.Tab) {
        guard tab == page.tab else { return }
        reselect.fire(tab)
        let inSubState: Bool
        switch tab {
        case .chaavi: inSubState = chaavi.kind != .all || chaavi.scope != nil
        case .ghar: inSubState = gharFilter != .everywhere
        case .system: inSubState = systemFocus != nil
        case .dadi, .planner: inSubState = false
        }
        switch TabReselect.reset(tab: tab, page: page, inSubState: inSubState) {
        case .chatsList: show(.dadi)
        case .chaaviEverything:
            withAnimation(Motion.settle) {
                chaavi.kind = .all
                chaavi.scope = nil
            }
        case .gharEverywhere: withAnimation(Motion.settle) { gharFilter = .everywhere }
        case .systemOverview: systemFocus = nil
        case .none: break
        }
    }

    /// Chats, with the open thread pushed on it. The stack follows `dadiPage`, so opening a thread, the edge-swipe back and a
    /// re-tap of the Chats tab are all the system's push and pop, and a thread brings its own composer with its page.
    private var dadiContent: some View {
        NavigationStack(path: Binding {
            ChatsRoute.path(for: dadiPage)
        } set: { path in
            let next = ChatsRoute.page(for: path)
            dadiPage = next
            if page.tab == .dadi { page = next }
        }) {
            ChatsView(threads: store.threads, filter: $chatsFilter, running: store.running(of:), error: store.error, loading: !store.loaded, retry: { Task { await store.load(services.hath) } }) { agentId in
                show(.thread(agentId))
            } details: { agentId in
                agentSheet = agentId
            }
            .background { FieldBloom() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { agentId in
                ThreadView(hath: services.hath, nas: services.nas, agentId: agentId, name: store.name(of: agentId), live: store.live, running: store.running(of: agentId), counts: store.counts(of: agentId), connections: store.connections, draft: drafts.draft(for: agentId)) { seq in
                    Task { await store.markRead(services.hath, agentId: agentId, through: seq) }
                } details: {
                    agentSheet = agentId
                }
                .background { FieldBloom() }
                .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    /// What the dock's accessory shows for the open page.
    private var presentation: DockPresentation {
        DockPresentation.of(page: page)
    }

    /// The Chats tab's badge: Ankur's unread replies.
    private var chatsBadge: Int { store.threads.reduce(0) { $0 + $1.unread } }

    /// Hands the composer's words to the router and toasts where they went. A
    /// failed run keeps the draft, copies it to the clipboard and toasts the
    /// router's own words; tapping the toast reopens the composer.
    private func sendToRouter() {
        router.send(services.hath, nas: services.nas) { messages in
            guard let first = messages.first else { return }
            let agent = first.toAgentId
            toaster.show(Toast(key: "routed", title: "Sent to \(store.name(of: agent))", detail: first.content, symbol: "checkmark.circle.fill") { show(.thread(agent)) })
        } failed: { message in
            UIPasteboard.general.string = router.draft
            toaster.show(Toast(key: "router-send-failed", title: "Not sent, copied to your clipboard", detail: message, symbol: "exclamationmark.triangle.fill", failure: true) { router.compose() })
        }
    }

    /// A page on the field under its floating bar, running the full height
    /// of the screen.
    private func chrome(_ content: some View, tab: HomeView.Tab) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { FieldBloom() }
            .scrollEdgeEffectStyle(.soft, for: .all)
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
            if tab == .planner, planner.section == .checklist {
                NameBubble(title: "Checklist", details: nil)
            } else if tab == .planner {
                Menu {
                    Picker("View", selection: Binding(get: { planner.mode }, set: { mode in withAnimation(Motion.settle) { planner.show(mode) } })) {
                        ForEach(PlannerMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(planner.mode.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.ink)
                            .contentTransition(.opacity)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.inkFaint)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityLabel("Planner view: \(planner.mode.rawValue)")
                .sensoryFeedback(.selection, trigger: planner.mode)
            } else if let title = title(of: shown) {
                NameBubble(title: title, details: shown.isThread ? { if case .thread(let agentId) = shown { agentSheet = agentId } } : nil)
                    .id(title)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
            Spacer()
            if tab == .chaavi {
                Button { creatingItem = true } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("New login or note")
            } else if shown.isThread {
                RouterMark(active: store.routing)
                    .frame(width: 52, height: 52)
                    .opacity(store.routing ? 1 : 0)
            } else {
                Color.clear.frame(width: 52, height: 52)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .opacity(arrived ? 1 : 0)
        .animation(Motion.snap, value: shown)
    }

    /// The page's name for its bubble; the Chats list has none, its search sits beside the menu button.
    private func title(of page: HomeView.Page) -> String? {
        switch page {
        case .dadi: nil
        case .thread(let agentId): store.name(of: agentId)
        case .planner: "Planner"
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
    /// Opens the thread of the agent a Planner item belongs to, with Ankur's RSVP ready in its composer when given.
    private func plannerMessage(_ agentId: String, ready text: String?) {
        if let text { drafts.draft(for: agentId).text = text }
        show(.thread(agentId))
    }

    private func show(_ next: HomeView.Page) {
        withAnimation(Motion.settle) {
            if next.tab == .dadi { dadiPage = next }
            page = next
        }
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
