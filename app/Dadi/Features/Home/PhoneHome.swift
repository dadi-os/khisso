import SwiftUI

/// The iPhone's Home: one page at a time on the field, with the drawer lying
/// underneath. Swipe from the left edge or tap the menu button and the page
/// slides right to uncover it, following the finger and springing open or
/// closed by where and how fast it was let go. Opening it puts the keyboard
/// away; a swipe left anywhere on the page, or a tap on it, closes it. Pages
/// run the full height of the screen: their content scrolls up under the
/// floating menu and compose buttons and the page's name in its glass bubble,
/// on past the Dynamic Island.
struct PhoneHome: View {
    let services: Services
    let wordmark: Namespace.ID
    let store: HomeStore
    @Binding var page: HomeView.Page

    @State private var open = false
    @State private var drag: CGFloat = 0
    @State private var opened = 0
    /// False until Home has settled in from Connecting, so the bar fades in
    /// around the wordmark instead of arriving with it.
    @State private var arrived = false
    /// True while a sideways drag is moving the drawer and just after, so the
    /// row a swipe ends on is not taken as a tap.
    @State private var swiping = false

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
                pageView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { FieldBloom() }
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
                    .shadow(color: .black.opacity(0.14 * progress), radius: 18, x: -4)
                    .offset(x: shift)
            }
            .gesture(open ? drawerDrag(width: width) : nil)
        }
        .sensoryFeedback(.selection, trigger: opened)
        .onChange(of: page, initial: true) { _, shown in
            if case .thread(let agentId) = shown { store.read(agentId) } else { store.read(nil) }
        }
        .onAppear { withAnimation(Motion.settle.delay(0.35)) { arrived = true } }
    }

    private var pageView: some View {
        Group {
            switch page {
            case .dadi:
                DadiView(hath: services.hath, name: store.name(of:), wordmark: wordmark) { agentId in
                    withAnimation(Motion.settle) { page = .thread(agentId) }
                }
                .transition(.opacity)
            case .thread(let agentId):
                ThreadView(hath: services.hath, agentId: agentId, name: store.name(of: agentId), live: store.live, lanes: store.lanes(of: agentId))
                    .id(agentId)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaBar(edge: .top) { topBar }
    }

    private var topBar: some View {
        HStack {
            Button { set(open: !open) } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Open sidebar")
            Spacer()
            if let title {
                NameBubble(title: title, hue: hue)
                    .id(title)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
            Spacer()
            Button { choose(.dadi) } label: {
                Image(systemName: "square.and.pencil")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .opacity(page == .dadi ? 0 : 1)
            .disabled(page == .dadi)
            .accessibilityLabel("Talk to Dadi")
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .opacity(arrived ? 1 : 0)
        .animation(Motion.snap, value: page)
    }

    /// The page's name for its bubble; Talk to Dadi has none.
    private var title: String? {
        switch page {
        case .dadi: nil
        case .thread(let agentId): store.name(of: agentId)
        case .timeline: "Timeline"
        case .ghar: "Ghar"
        case .chaavi: "Chaavi"
        case .system: "System"
        }
    }

    /// The agent's color beside its name in a thread.
    private var hue: Color? {
        if case .thread(let agentId) = page { return Agent.hue(agentId) }
        return nil
    }

    /// Shows `next` and closes the drawer.
    private func choose(_ next: HomeView.Page) {
        withAnimation(Motion.settle) { page = next }
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

/// Puts the keyboard away, whichever field has it.
@MainActor
private func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// The drawer: Talk to Dadi, dadi's pages, then every agent thread with its
/// unread count, on a frosted sheet that runs to every edge of the screen.
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
            VStack(spacing: 8) {
                pageTile("Timeline", systemImage: "calendar", page: .timeline)
                pageTile("Ghar", systemImage: "house.fill", page: .ghar)
                pageTile("Chaavi", systemImage: "key.fill", page: .chaavi)
                pageTile("System", systemImage: "server.rack", page: .system)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
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
                            ThreadRow(thread: thread, lanes: lanes, selected: selected, unread: store.unread[thread.agentId] ?? 0)
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

    /// A full-width drawer tile that opens one of dadi's pages, lit sage while
    /// its page is open.
    private func pageTile(_ title: String, systemImage: String, page target: HomeView.Page) -> some View {
        let current = page == target
        return Button { choose(target) } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(current ? Color.bone : .sageDeep)
                    .frame(width: 36, height: 36)
                    .background(current ? AnyShapeStyle(Color.sageDeep) : AnyShapeStyle(Color.sage.opacity(0.16)), in: .rect(cornerRadius: 11, style: .continuous))
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.inkFaint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(current ? Color.sage.opacity(0.16) : Color.bone.opacity(0.45), in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(current ? Color.sage.opacity(0.4) : .sageLine.opacity(0.3), lineWidth: 1))
            .contentShape(.rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(Motion.snap, value: current)
    }
}

/// A page's name in a glass bubble, as thaali's pane header: the agent's color
/// as a dot when it is a thread.
private struct NameBubble: View {
    let title: String
    let hue: Color?

    var body: some View {
        HStack(spacing: 7) {
            if let hue {
                Circle().fill(hue).frame(width: 8, height: 8)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
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
