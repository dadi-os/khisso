#if os(iOS)
import SwiftUI

/// The iPhone's Home: one page at a time on the field, with a glass drawer
/// underneath that the page slides off of. Swipe from the left edge or tap the
/// menu button to open it; the page follows the finger and springs to open or
/// closed by where and how fast it was let go.
struct PhoneHome: View {
    let hath: HathClient
    let nodeName: String?
    let wordmark: Namespace.ID
    let store: HomeStore
    @Binding var page: HomeView.Page

    @State private var open = false
    @State private var drag: CGFloat = 0
    @State private var opened = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far from the left edge a swipe has to start to open the drawer.
    private let edge: CGFloat = 32

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width * 0.84, 340)
            let shift = max(0, min(width, (open ? width : 0) + drag))
            let progress = shift / width
            ZStack(alignment: .leading) {
                FieldBloom()
                Drawer(store: store, nodeName: nodeName, page: page, choose: choose)
                    .frame(width: width)
                    .offset(x: (progress - 1) * 40)
                    .opacity(progress)
                pageView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { FieldBloom() }
                    .clipShape(.rect(cornerRadius: progress * 44, style: .continuous))
                    .shadow(color: .black.opacity(0.18 * progress), radius: 24, x: -6)
                    .overlay {
                        Color.black.opacity(0.12 * progress)
                            .clipShape(.rect(cornerRadius: progress * 44, style: .continuous))
                            .allowsHitTesting(open)
                            .onTapGesture { set(open: false) }
                    }
                    .scaleEffect(reduceMotion ? 1 : 1 - progress * 0.06, anchor: .leading)
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
                DadiView(hath: hath, wordmark: wordmark) { agentId in
                    withAnimation(Motion.settle) { page = .thread(agentId) }
                }
                .transition(.opacity)
            case .thread(let agentId):
                ThreadView(hath: hath, agentId: agentId, name: store.name(of: agentId), live: store.live)
                    .id(agentId)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
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
                drag = value.translation.width
            }
            .onEnded { value in
                guard open || value.startLocation.x < edge else { return }
                let end = (open ? width : 0) + value.predictedEndTranslation.width
                set(open: end > width / 2)
            }
    }
}

/// The drawer: Talk to Dadi, then every agent thread, with this device's name
/// and connection at the foot, on glass over the field.
private struct Drawer: View {
    let store: HomeStore
    let nodeName: String?
    let page: HomeView.Page
    let choose: (HomeView.Page) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("દાદી")
                .font(.wordmark(34))
                .foregroundStyle(.sageDeep)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)
            Button { choose(.dadi) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(page == .dadi ? Color.bone : .sageDeep)
                        .frame(width: 34, height: 34)
                        .background(page == .dadi ? AnyShapeStyle(Color.sageDeep) : AnyShapeStyle(Color.sage.opacity(0.16)), in: .circle)
                    Text("Talk to Dadi")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.ink)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(page == .dadi ? Color.sage.opacity(0.14) : .clear, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
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
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
                .ignoresSafeArea()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.liveError == nil ? Color.sage : .clay)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(nodeName ?? "This iPhone")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.ink)
                Text(store.liveError ?? "Online on dadi")
                    .font(.caption)
                    .foregroundStyle(.inkMuted)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
#endif
