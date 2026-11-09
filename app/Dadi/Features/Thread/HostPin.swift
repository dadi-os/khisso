import SwiftUI

/// The strip above an open agent thread: the agent's newest live browser and newest live terminal as small
/// live previews, a browser in a window with its active tab's address, a terminal's last lines. Tapping one
/// opens its card. Shown only while the app is forward and a live task exists; the tasks are read again on
/// every Nas change and, while a browser is live, every two seconds, since the page in front changes with no
/// event announcing it. Leaving the thread closes the streams.
struct HostPin: View {
    let hath: HathClient
    let nas: NasClient
    let agentId: String
    /// The agent's name.
    let owner: String

    @State private var pins = PinnedTasks(of: [])
    @State private var problem: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LiveData.self) private var live: LiveData?

    private static let poll: Duration = .seconds(2)

    private struct Reload: Hashable {
        let changes: Int
        let forward: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if scenePhase == .active, !pins.isEmpty {
                HStack(spacing: 8) {
                    if let browser = pins.browser { PinCard(hath: hath, nas: nas, task: browser, owner: owner) { await load() } }
                    if let terminal = pins.terminal { PinCard(hath: hath, nas: nas, task: terminal, owner: owner) { await load() } }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let problem {
                Label("Helper tasks could not be read: \(problem)", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, pins.isEmpty && problem == nil ? 0 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { if scenePhase == .active, !pins.isEmpty || problem != nil { Rectangle().fill(.ultraThinMaterial) } }
        .animation(Motion.settle, value: pins)
        .task(id: Reload(changes: live?.nas ?? 0, forward: scenePhase == .active)) { await follow() }
    }

    /// Reads the tasks now, and again every `poll` while a browser is live.
    private func follow() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            await load()
            guard pins.browser != nil else { return }
            do { try await Task.sleep(for: Self.poll) } catch { return }
        }
    }

    private func load() async {
        do {
            pins = PinnedTasks(of: try await nas.tasks().filter { $0.owner == agentId })
            problem = nil
        } catch is CancellationError {
            return
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// One pin: a browser drawn as a window (three dots, an address pill showing the active tab's address, then
/// the live page) or a terminal (its address, then its last lines). Only active tasks are pinned, so the card
/// carries no status. The whole card is the button that opens the task card.
private struct PinCard: View {
    let hath: HathClient
    let nas: NasClient
    let task: NasTask
    let owner: String
    let changed: () async -> Void

    @State private var acting = false

    private static let width: CGFloat = 200
    private static let screenHeight = width * 9 / 16

    var body: some View {
        Button { acting = true } label: {
            preview
        }
        .buttonStyle(.plain)
        .frame(maxWidth: Self.width)
        .accessibilityLabel(task.kind == "browser" ? "Open the browser" : "Open the terminal")
        .taskSheet(isPresented: $acting, hath: hath, nas: nas, task: task, owner: owner, changed: changed)
    }

    @ViewBuilder
    private var preview: some View {
        if task.kind == "browser", let resource = task.resource, let id = Int(resource) {
            BrowserWindow(nas: nas, browserId: id, address: task.activeUrl, compact: true)
        } else if let resource = task.resource {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal").font(.system(size: 10)).foregroundStyle(.inkMuted)
                    Text("\(task.route) \u{00B7} \(resource)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.inkMuted).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                TaskTerminal(nas: nas, terminalId: resource, lines: 12, fontSize: 8)
                    .frame(height: Self.screenHeight, alignment: .bottom)
                    .clipped()
            }
            .background(.boneRaised, in: .rect(cornerRadius: 12, style: .continuous))
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.sageLine.opacity(0.7), lineWidth: 1) }
        }
    }
}
