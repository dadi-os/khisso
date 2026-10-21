#if os(iOS)
import SwiftUI

/// The iPhone's Home: one page at a time on the field, with the drawer lying
/// underneath. Swipe from the left edge or tap the menu button and the page
/// slides right to uncover it, following the finger and springing open or
/// closed by where and how fast it was let go. Opening it puts the keyboard
/// away; a swipe left anywhere on the page, or a tap on it, closes it.
struct PhoneHome: View {
    let services: Services
    let wordmark: Namespace.ID
    let store: HomeStore
    @Binding var page: HomeView.Page

    @State private var open = false
    @State private var drag: CGFloat = 0
    @State private var opened = 0

    /// How far from the left edge a swipe has to start to open the drawer.
    private let edge: CGFloat = 32

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width * 0.84, 340)
            let shift = max(0, min(width, (open ? width : 0) + drag))
            let progress = shift / width
            ZStack(alignment: .leading) {
                FieldBloom()
                Drawer(store: store, page: page, choose: choose)
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
                    .shadow(color: .black.opacity(0.14 * progress), radius: 18, x: -4)
                    .offset(x: shift)
            }
            .gesture(drawerDrag(width: width))
        }
        .sensoryFeedback(.selection, trigger: opened)
    }

    @ViewBuilder
    private var pageView: some View {
        VStack(spacing: 0) {
            topBar
            switch page {
            case .dadi:
                DadiView(hath: services.hath, wordmark: wordmark) { agentId in
                    withAnimation(Motion.settle) { page = .thread(agentId) }
                }
                .transition(.opacity)
            case .thread(let agentId):
                ThreadView(hath: services.hath, agentId: agentId, name: store.name(of: agentId), live: store.live, running: store.running.contains(agentId))
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
            Group {
                switch page {
                case .dadi:
                    Text(" ")
                case .thread(let agentId):
                    Text(store.name(of: agentId))
                case .timeline:
                    Text("Timeline")
                case .ghar:
                    Text("Ghar")
                case .chaavi:
                    Text("Chaavi")
                case .system:
                    Text("System")
                }
            }
            .font(.headline)
            .foregroundStyle(.ink)
            .lineLimit(1)
            .contentTransition(.opacity)
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
        .padding(.bottom, 6)
        .animation(Motion.snap, value: page)
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
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard open || value.startLocation.x < edge else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if !open && drag == 0 { dismissKeyboard() }
                drag = value.translation.width
            }
            .onEnded { value in
                guard open || value.startLocation.x < edge else { return }
                let end = (open ? width : 0) + value.predictedEndTranslation.width
                set(open: end > width / 2)
            }
    }
}

/// Puts the keyboard away, whichever field has it.
private func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// The drawer: Talk to Dadi, dadi's pages, then every agent thread, on glass
/// over the field.
private struct Drawer: View {
    let store: HomeStore
    let page: HomeView.Page
    let choose: (HomeView.Page) -> Void

    var body: some View {
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
                    Text("દ")
                        .font(.wordmark(21))
                        .foregroundStyle(.sageText)
                        .inkCentered(.letter, size: 21)
                        .frame(width: 34, height: 34)
                        .background(.sage.opacity(page == .dadi ? 0.26 : 0.14), in: .circle)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Talk to Dadi")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.ink)
                        Text("Start something new")
                            .font(.footnote)
                            .foregroundStyle(.inkFaint)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(page == .dadi ? Color.sage.opacity(0.14) : .clear, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            VStack(spacing: 2) {
                pageRow("Timeline", systemImage: "calendar", page: .timeline)
                pageRow("Ghar", systemImage: "house", page: .ghar)
                pageRow("Chaavi", systemImage: "key", page: .chaavi)
                pageRow("System", systemImage: "server.rack", page: .system)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            ScrollView {
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
                        Button { choose(.thread(thread.agentId)) } label: {
                            ThreadRow(thread: thread, running: store.running.contains(thread.agentId), selected: selected)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selected ? Color.sage.opacity(0.14) : .clear, in: .rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
                .ignoresSafeArea()
        }
    }

    /// A drawer row that opens one of dadi's pages.
    private func pageRow(_ title: String, systemImage: String, page target: HomeView.Page) -> some View {
        Button { choose(target) } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.sageDeep)
                    .frame(width: 34, height: 34)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.ink)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(page == target ? Color.sage.opacity(0.14) : .clear, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
#endif
