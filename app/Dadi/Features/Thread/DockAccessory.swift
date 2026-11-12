import PhotosUI
import SwiftUI

/// The thread the dock's accessory writes to.
struct DockThread {
    let agentId: String
    let name: String
    let draft: ThreadDraft
    /// Sends the draft to the agent.
    let send: () -> Void
}

/// Who the dock's one composer is for.
enum DockDestination: Equatable {
    case dadi
    case thread(agentId: String)

    /// A thread's composer while a thread is open; Dadi's bar on every other page, and while Dadi's
    /// own composer is up over a thread, so two fields for two destinations never show together.
    static func of(openThread: String?, routerComposing: Bool) -> DockDestination {
        guard let openThread, !routerComposing else { return .dadi }
        return .thread(agentId: openThread)
    }
}

/// What the tab bar's bottom accessory holds. On every page but a thread it is Talk to Dadi's bar.
/// In a thread it is that thread's composer, with the Talk to Dadi mark beside it that opens Dadi's
/// composer over the page; the composer is the dock's only text field.
struct DockAccessory: View {
    let router: RouterDock
    /// True while any router run is in flight.
    let active: Bool
    /// False while dadi is out of reach.
    let online: Bool
    /// The open thread, or nil on every other page.
    let thread: DockThread?

    var body: some View {
        switch DockDestination.of(openThread: thread?.agentId, routerComposing: router.composing) {
        case .thread:
            if let thread {
                ThreadAccessory(thread: thread, router: router, active: active, online: online)
            }
        case .dadi:
            RouterDockBar(dock: router, active: active, online: online)
        }
    }
}

/// A thread's composer in the accessory: attach, the field, send once there is something to send,
/// and the Talk to Dadi mark. Beside the condensed tab bar the attach button goes and the field
/// shrinks to a capsule; both placements hold the same field, so a draft and the cursor stay put
/// as the bar condenses and expands.
private struct ThreadAccessory: View {
    let thread: DockThread
    let router: RouterDock
    let active: Bool
    let online: Bool

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @FocusState private var focused: Bool
    @State private var camera = CameraModel()
    @State private var cameraOpen = false
    @State private var libraryOpen = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var problem: String?

    var body: some View {
        @Bindable var draft = thread.draft
        HStack(spacing: 4) {
            if placement != .inline {
                attach
            }
            TextField("Message \(thread.name)\u{2026}", text: $draft.text, axis: .vertical)
                .focused($focused)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .foregroundStyle(.ink)
                .padding(.horizontal, placement == .inline ? 8 : 4)
                .onSubmit(thread.send)
            if draft.canSend || draft.sending {
                sendButton
            }
            Button { router.compose() } label: {
                RouterMark(active: active)
                    .frame(width: 40, height: 40)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(!online)
            .opacity(online ? 1 : 0.6)
            .accessibilityLabel("Talk to Dadi")
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 44)
        .onChange(of: draft.focusRequests) { focused = true }
        .photosPicker(isPresented: $libraryOpen, selection: $picked, maxSelectionCount: max(1, DraftPhoto.limit - draft.photos.count), matching: .images)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await addPicked(items) }
        }
        .fullScreenCover(isPresented: $cameraOpen) { cameraCover }
        .task { await camera.prepare() }
        .alert("Photo not added", isPresented: Binding { problem != nil } set: { if !$0 { problem = nil } }) {
            Button("OK") {}
        } message: {
            Text(problem ?? "")
        }
    }

    private var attach: some View {
        Menu {
            Button { openCamera() } label: { Label("Camera", systemImage: "camera") }
            Button { libraryOpen = true } label: { Label("Photos", systemImage: "photo.on.rectangle") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.sageDeep)
                .frame(width: 40, height: 40)
                .contentShape(.circle)
        }
        .accessibilityLabel("Add a photo")
    }

    private var sendButton: some View {
        Button(action: thread.send) {
            ZStack {
                if thread.draft.sending {
                    ProgressView().controlSize(.small).tint(.bone)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.bone)
                }
            }
            .frame(width: 34, height: 34)
            .background(.sageDeep, in: .circle)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!thread.draft.canSend)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel("Send")
    }

    private var cameraCover: some View {
        CameraPanel(camera: camera, count: thread.draft.photos.count, dismissing: false, add: { thread.draft.photos.append($0) }, close: closeCamera)
            .background(.black)
            .ignoresSafeArea()
            .task { await camera.start() }
    }

    private func openCamera() {
        focused = false
        cameraOpen = true
        Task { await camera.warm() }
    }

    private func closeCamera() {
        cameraOpen = false
        camera.release()
    }

    /// Adds the picked library photos, as many as the message has room for.
    private func addPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                thread.draft.photos.append(try await DraftPhoto.picked(item))
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
