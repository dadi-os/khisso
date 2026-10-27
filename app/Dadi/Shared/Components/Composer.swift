import Combine
import PhotosUI
import SwiftUI
import UIKit

/// The message field and its send button, two shapes of one liquid glass:
/// once there is something to send, the button flows out of the field's end
/// on one spring and the field draws in to make room, and it flows back in
/// when the field empties. The glass only melds while the shapes move: at rest
/// the gap between them is wider than the container's merge distance, so no
/// bridge of glass is left between them. Sending puts the keyboard away, a beat after the bubble. The
/// field's rim answers the agent's lanes as thaali's does: quieter while it
/// thinks, sage while it works.
struct Composer: View {
    @Binding var text: String
    /// Photos waiting to go with the message.
    @Binding var photos: [DraftPhoto]
    let placeholder: String
    /// A send is in flight: the button spins and another send waits.
    let busy: Bool
    var lanes: Set<Lane> = []
    /// Puts the cursor in the field as soon as it shows, for a page opened to write.
    var focusOnAppear = false
    let send: () -> Void

    @Namespace private var glass
    @FocusState private var focused: Bool
    @State private var attach = Attach.closed
    @State private var camera = CameraModel()
    @State private var libraryOpen = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var problem: String?
    @State private var opened = 0
    @State private var dismissing = false
    /// The composer's width, which the open viewfinder fills.
    @State private var width: CGFloat = 0

    /// What the plus is showing: itself, the choice of camera or photos, or
    /// the camera.
    private enum Attach: Equatable {
        case closed, choosing, camera
    }

    /// How tall the viewfinder grows to.
    private static let cameraHeight: CGFloat = 430
    /// How tall the choice of camera or photos is.
    private static let chooserHeight: CGFloat = 104

    /// The gap between field and button at rest, wider than `merge`.
    private let gap: CGFloat = 10
    /// How near the two shapes must be for their glass to meld.
    private let merge: CGFloat = 6

    private var rim: Color {
        if lanes.contains(.conversation) { return .sageLine.opacity(0.28) }
        if lanes.contains(.reasoning) { return .sage.opacity(0.36) }
        return .sageLine.opacity(0.42)
    }

    private var ready: Bool { !busy && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty) }

    /// The button is out while there is something to send or a send is in flight.
    private var showsSend: Bool { ready || busy }

    var body: some View {
        VStack(spacing: 0) {
            if !photos.isEmpty {
                PhotoStrip(photos: $photos)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomLeading)))
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
            fieldRow
        }
        .animation(Motion.settle, value: photos)
        .animation(Motion.snap, value: problem)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: opened)
        .frame(maxWidth: 680)
        .photosPicker(isPresented: $libraryOpen, selection: $picked, maxSelectionCount: max(1, DraftPhoto.limit - photos.count), matching: .images)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await addPicked(items) }
        }
        .task { await camera.prepare() }
        .onAppear { if focusOnAppear { focused = true } }
    }

    /// The plus, which is also the attachment chooser and the viewfinder: it
    /// grows from a glass circle at the field's start into a choice of Camera
    /// or Photos (the camera warming up behind it), and Camera grows it on into
    /// the viewfinder, the field and send button giving way; it shrinks back
    /// into the plus when closed. The viewfinder is laid out at its open size
    /// from the start and the growing surface uncovers it from the plus's
    /// corner, so the live preview never resizes mid-animation.
    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: attach == .choosing ? 30 : 36, style: .continuous)
        return ZStack {
            switch attach {
            case .camera:
                CameraPanel(camera: camera, count: photos.count, dismissing: dismissing, add: { photos.append($0) }, close: closeCamera)
                    .frame(width: max(width, 46), height: Self.cameraHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.16)),
                        removal: .opacity.animation(.easeIn(duration: 0.2).delay(0.12))
                    ))
            case .choosing:
                chooser
                    .frame(width: max(width, 46), height: Self.chooserHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.06)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))
                    ))
            case .closed:
                Button(action: openChooser) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.sageDeep)
                        .frame(width: 46, height: 46)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a photo")
                .transition(.opacity)
            }
        }
        .frame(maxWidth: attach == .closed ? 46 : .infinity)
        .frame(height: attach == .camera ? Self.cameraHeight : attach == .choosing ? Self.chooserHeight : 46)
        .background(Color.black.opacity(attach == .camera ? 1 : 0), in: shape)
        .clipShape(shape)
        .glassEffect(.regular.interactive(), in: shape)
        .glassEffectID("plus", in: glass)
    }

    /// Camera or Photos, as two tiles, with a way back to the plus.
    private var chooser: some View {
        HStack(spacing: 10) {
            chooserTile("Camera", symbol: "camera.fill", action: openCamera)
            chooserTile("Photos", symbol: "photo.on.rectangle", action: openLibrary)
            Button(action: closeChooser) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.inkMuted)
                    .frame(width: 40, height: 40)
                    .background(.ink.opacity(0.06), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(12)
    }

    private func chooserTile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.sageDeep)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.ink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.sage.opacity(0.14), in: .rect(cornerRadius: 22, style: .continuous))
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    private var fieldRow: some View {
        GlassEffectContainer(spacing: merge) {
            HStack(alignment: .bottom, spacing: gap) {
                surface
                if attach == .closed {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .focused($focused)
                        .lineLimit(1...6)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.ink)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .onSubmit(submit)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 23, style: .continuous))
                        .glassEffectID("field", in: glass)
                        .overlay {
                            RoundedRectangle(cornerRadius: 23, style: .continuous)
                                .strokeBorder(rim, lineWidth: 1)
                                .animation(Motion.settle, value: lanes)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                    if showsSend {
                        Button(action: submit) {
                            ZStack {
                                if busy {
                                    ProgressView().controlSize(.small).tint(.bone)
                                } else {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(.bone)
                                }
                            }
                            .frame(width: 46, height: 46)
                            .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(.sageDeep).interactive(), in: .circle)
                        .glassEffectID("send", in: glass)
                        .disabled(!ready)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityLabel("Send")
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: attach)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: showsSend)
    }

    /// Puts the keyboard away and opens the choice of camera or photos,
    /// warming the camera up behind it.
    private func openChooser() {
        focused = false
        problem = nil
        attach = .choosing
        opened += 1
        Task { await camera.warm() }
    }

    private func closeChooser() {
        attach = .closed
    }

    /// Grows the choice on into the viewfinder: nobody types and shoots at once.
    private func openCamera() {
        attach = .camera
        opened += 1
        Task { await camera.start() }
    }

    /// Opens the photo library and folds the choice back into the plus.
    private func openLibrary() {
        attach = .closed
        libraryOpen = true
    }

    /// Adds the picked library photos, as many as the message has room for.
    private func addPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                photos.append(try await DraftPhoto.picked(item))
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    /// Closes in one motion: the controls fade while the surface shrinks back
    /// into the plus, the frozen preview clipped inside it, and the camera keeps
    /// running a while so opening it again is instant.
    private func closeCamera() {
        guard attach == .camera, !dismissing else { return }
        dismissing = true
        attach = .closed
        camera.release()
        Task {
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            dismissing = false
        }
    }

    /// How long the sent bubble leads before the keyboard starts down, so the
    /// two motions follow one another instead of landing together.
    private let keyboardLag: Duration = .milliseconds(160)

    /// Sends, then eases the keyboard down behind the bubble.
    private func submit() {
        guard ready else { return }
        closeCamera()
        closeChooser()
        send()
        Task {
            do { try await Task.sleep(for: keyboardLag) } catch { return }
            withAnimation(Motion.settle) { focused = false }
        }
    }
}

/// Where a page's composer sits above the bottom of the screen: low, just
/// over the home indicator as iMessage's field sits, and a little higher over
/// the keyboard so the glass never meets it.
private struct ComposerInset: ViewModifier {
    @State private var keyboard = false

    /// Above the home indicator.
    private let resting: CGFloat = 5
    /// Above the keyboard.
    private let raised: CGFloat = 10

    /// An ease as long as the keyboard's own move in `note`, so the composer
    /// settles with it rather than ahead of it.
    private static func follow(_ note: Notification) -> Animation {
        let seconds = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        return .easeInOut(duration: seconds)
    }

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboard ? raised : resting)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
                withAnimation(Self.follow(note)) { keyboard = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
                withAnimation(Self.follow(note)) { keyboard = false }
            }
    }
}

extension View {
    /// Sits a composer at the bottom of its page: just above the home
    /// indicator, or above the keyboard while it is up.
    func composerInset() -> some View {
        modifier(ComposerInset())
    }
}


/// The photos waiting to be sent, as a row of thumbnails each with a button to
/// take it back out.
private struct PhotoStrip: View {
    @Binding var photos: [DraftPhoto]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(photos) { photo in
                    Image(uiImage: photo.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 14, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                photos.removeAll { $0.id == photo.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(.bone)
                                    .frame(width: 20, height: 20)
                                    .background(.ink.opacity(0.75), in: .circle)
                                    .frame(width: 32, height: 32)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .offset(x: 8, y: -8)
                            .accessibilityLabel("Remove photo")
                        }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 12)
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
