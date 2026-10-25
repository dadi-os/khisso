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
    /// True while the open thread's agent sheet is up.
    @State private var showingAgent = false
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
                Drawer(store: store, page: page) { next in
                    guard !swiping else { return }
                    choose(next)
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
        .sheet(isPresented: $showingAgent) {
            if case .thread(let agentId) = dadiPage {
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
                    TimelinePage(yaad: services.yaad) { agentId in
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
                }
                    .id(agentId)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            default:
                DadiView(hath: services.hath, name: store.name(of:), wordmark: wordmark) { agentId in
                    show(.thread(agentId))
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
            if let title = title(of: shown) {
                NameBubble(title: title, details: shown.isThread ? { showingAgent = true } : nil)
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

/// The drawer: Talk to Dadi, then every agent thread with its unread count,
/// on a frosted sheet that runs to every edge of the screen.
private struct Drawer: View {
    let store: HomeStore
    let page: HomeView.Page
    let choose: (HomeView.Page) -> Void

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
                Button { choose(.dadi) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            if store.routing {
                                PulseOut()
                            }
                            Text("દ")
                                .font(.wordmark(21))
                                .foregroundStyle(store.routing ? Color.sageDeep : .sageText)
                                .inkCentered(.letter, size: 21)
                                .frame(width: 34, height: 34)
                                .background(.sage.opacity(page == .dadi || store.routing ? 0.26 : 0.14), in: .circle)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Talk to Dadi")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.ink)
                            if store.routing {
                                HStack(spacing: 6) {
                                    ThinkingMark()
                                    Text("routing").font(.footnote).foregroundStyle(.sageText)
                                }
                                .transition(.opacity)
                            } else {
                                Text("Start something new")
                                    .font(.footnote)
                                    .foregroundStyle(.inkFaint)
                                    .transition(.opacity)
                            }
                        }
                        Spacer()
                    }
                    .animation(Motion.settle, value: store.routing)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(page == .dadi ? Color.sage.opacity(0.14) : .clear, in: .rect(cornerRadius: 16))
                    .contentShape(.rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                LazyVStack(alignment: .leading, spacing: 2) {
                    Text("AGENTS")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(.inkFaint)
                        .padding(.horizontal, 12)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                    if let error = store.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.danger)
                            .padding(12)
                    }
                    ForEach(store.threads) { thread in
                        let selected = page == .thread(thread.agentId)
                        let lanes = store.lanes(of: thread.agentId)
                        Button { choose(.thread(thread.agentId)) } label: {
                            ThreadRow(thread: thread, lanes: lanes, unread: thread.unread)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selected ? Color.sage.opacity(0.14) : .clear, in: .rect(cornerRadius: 16))
                                .laneSheen(lanes.contains(.reasoning), in: .rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .scrollIndicators(.hidden)
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

    var body: some View {
        let label = HStack(spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.ink)
                .lineLimit(1)
            if details != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.inkFaint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(details == nil ? .regular : .regular.interactive(), in: .capsule)
        if let details {
            Button(action: details) { label }
                .buttonStyle(.plain)
                .accessibilityHint("Shows details and activity")
        } else {
            label
        }
    }
}

/// Thaali's live ring: a sage disc swelling out and fading behind a busy mark.
private struct PulseOut: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(.sage.opacity(0.45))
            .frame(width: 34, height: 34)
            .phaseAnimator([false, true]) { ring, out in
                ring.scaleEffect(out ? 1.55 : 1).opacity(out ? 0 : 0.55)
            } animation: { out in
                out && !reduceMotion ? .easeOut(duration: 2.4) : nil
            }
    }
}
