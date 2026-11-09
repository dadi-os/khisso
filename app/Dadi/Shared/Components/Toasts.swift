import SwiftUI

/// The part of dadi a toast is about, which picks its symbol.
enum ToastModule {
    case ghar, chaavi, yaad, hath, system, timeline, dadi

    var symbol: String {
        switch self {
        case .ghar: "house"
        case .chaavi: "key"
        case .yaad: "brain"
        case .hath: "point.3.connected.trianglepath.dotted"
        case .system: "server.rack"
        case .timeline: "calendar"
        case .dadi: "paperplane"
        }
    }
}

/// One toast: a title and detail, folded with an earlier toast of the same key.
struct Toast: Identifiable, Equatable {
    /// Toasts with the same key fold into one.
    let key: String
    let title: String
    var detail: String?
    /// The symbol before the title; a module's symbol, or the chat bubble when none applies.
    var symbol = "bubble.left.fill"
    /// True for a failure: the symbol and title read in the danger color.
    var failure = false
    /// Runs when the toast is tapped.
    var open: (@MainActor () -> Void)?

    var id: String { key }

    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.key == rhs.key && lhs.title == rhs.title && lhs.detail == rhs.detail
    }
}

/// The toasts on screen, newest first. A toast holds for five seconds, a
/// repeat of its key replaces it and restarts the hold, and a tap runs its
/// action and puts it away.
@MainActor
@Observable
final class Toaster {
    /// How long a toast holds.
    static let hold: Duration = .seconds(5)
    /// Most toasts on screen at once.
    private static let limit = 3

    private(set) var toasts: [Toast] = []
    private var holds: [String: Task<Void, Never>] = [:]

    /// Shows `toast`, folding it into one already up under its key.
    func show(_ toast: Toast) {
        withAnimation(Motion.snap) {
            toasts.removeAll { $0.key == toast.key }
            toasts.insert(toast, at: 0)
            if toasts.count > Self.limit { dismiss(toasts[Self.limit].key) }
        }
        holds[toast.key]?.cancel()
        holds[toast.key] = Task {
            do { try await Task.sleep(for: Self.hold) } catch { return }
            dismiss(toast.key)
        }
    }

    /// Puts the toast under `key` away.
    func dismiss(_ key: String) {
        holds[key]?.cancel()
        holds[key] = nil
        withAnimation(Motion.snap) { toasts.removeAll { $0.key == key } }
    }
}

/// The toasts, as glass cards 8 pt under the top bar.
struct ToastStack: View {
    let toaster: Toaster

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toaster.toasts) { toast in
                Button {
                    toast.open?()
                    toaster.dismiss(toast.key)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: toast.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(toast.failure ? Color.danger : .sageDeep)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(toast.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(toast.failure ? Color.danger : .ink)
                                .lineLimit(1)
                            if let detail = toast.detail {
                                Text(detail)
                                    .font(.footnote)
                                    .foregroundStyle(.inkMuted)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
                    .contentShape(.rect(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 520)
        .accessibilityElement(children: .contain)
    }
}
