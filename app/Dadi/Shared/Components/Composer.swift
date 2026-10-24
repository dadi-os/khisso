import Combine
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
    let send: () -> Void

    @Namespace private var glass
    @FocusState private var focused: Bool
    @State private var cameraOpen = false
    @State private var camera = CameraModel()
    @State private var opened = 0
    @State private var dismissing = false

    /// How tall the viewfinder grows to.
    private static let cameraHeight: CGFloat = 430

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
            fieldRow
        }
        .animation(Motion.settle, value: photos)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: opened)
        .frame(maxWidth: 680)
        .task { await camera.prepare() }
    }

    /// The plus, which is also the viewfinder: it grows from a glass circle at
    /// the field's start into the camera, the field and send button giving
    /// way, and shrinks back when the camera closes.
    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
        return ZStack {
            if cameraOpen {
                CameraPanel(camera: camera, count: photos.count, dismissing: dismissing, add: { photos.append($0) }, close: closeCamera)
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.1)), removal: .identity))
            } else {
                Button(action: openCamera) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.sageDeep)
                        .frame(width: 46, height: 46)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add photos")
                .transition(.opacity)
            }
        }
        .frame(maxWidth: cameraOpen ? .infinity : 46)
        .frame(height: cameraOpen ? Self.cameraHeight : 46)
        .background(Color.black.opacity(cameraOpen ? 1 : 0), in: shape)
        .clipShape(shape)
        .glassEffect(.regular.interactive(), in: shape)
        .glassEffectID("plus", in: glass)
    }

    private var fieldRow: some View {
        GlassEffectContainer(spacing: merge) {
            HStack(alignment: .bottom, spacing: gap) {
                surface
                if !cameraOpen {
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
        .animation(.spring(response: 0.58, dampingFraction: 0.8), value: cameraOpen)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: showsSend)
    }

    /// Puts the keyboard away and opens the camera: nobody types and shoots at once.
    private func openCamera() {
        focused = false
        cameraOpen = true
        opened += 1
        Task { await camera.start() }
    }

    /// Closes in two steps: the panel's content goes first, then the empty
    /// surface shrinks back into the button, so no live preview is resized.
    private func closeCamera() {
        guard cameraOpen, !dismissing else { return }
        dismissing = true
        camera.release()
        Task {
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            cameraOpen = false
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
