import AVFoundation
import PhotosUI
import SwiftUI

/// A UIView whose layer is the camera's preview.
private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct Viewfinder: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}

/// What the composer's plus grows into: the live viewfinder, filling the
/// surface the composer gives it. Pinch to zoom, double-tap to turn to the
/// front camera, the shutter in the middle with a plus for the photo library
/// on its left and the camera's light on its right; swipe down or tap the
/// grabber to close. Photos go to the composer as they are taken or picked,
/// and it stays open for more. It arrives in stages: the dark poster first,
/// the controls rising into place, and the live preview only once the surface
/// has finished growing, so the preview is never resized mid-animation. It
/// leaves the same way in reverse.
struct CameraPanel: View {
    let camera: CameraModel
    /// Photos already waiting, so the panel knows when the message is full.
    let count: Int
    /// The composer is closing: the content leaves before the surface shrinks.
    let dismissing: Bool
    let add: (DraftPhoto) -> Void
    let close: () -> Void

    /// Side buttons and the shutter's slot share this size, so the shutter sits centered.
    private static let button: CGFloat = 46
    private static let shutter: CGFloat = 74

    @State private var libraryOpen = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var problem: String?
    @State private var taking = false
    @State private var shutter = 0
    @State private var arrived = false
    /// The surface has finished growing, so the live preview may mount.
    @State private var settled = false
    @State private var turning = false
    @State private var flips = 0
    @State private var pinching = false
    @State private var zoomAtPinchStart: CGFloat = 1

    var body: some View {
        ZStack {
            viewfinder
                .opacity(arrived ? 1 : 0)
                .scaleEffect(arrived ? 1 : 1.06)
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            grabber
            zoomLabel
            controls
                .offset(y: arrived ? 0 : 28)
                .opacity(arrived ? 1 : 0)
        }
        .contentShape(.rect)
        .onTapGesture(count: 2, perform: turn)
        .gesture(pinch)
        .photosPicker(isPresented: $libraryOpen, selection: $picked, maxSelectionCount: max(1, DraftPhoto.limit - count), matching: .images)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await load(items) }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: shutter)
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: flips)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.86).delay(0.08)) { arrived = true } }
        .task {
            do { try await Task.sleep(for: .milliseconds(480)) } catch { return }
            withAnimation(.easeOut(duration: 0.3)) { settled = true }
        }
        .onChange(of: dismissing) { _, leaving in
            guard leaving else { return }
            settled = false
            withAnimation(.easeIn(duration: 0.17)) { arrived = false }
        }
    }

    @ViewBuilder
    private var viewfinder: some View {
        switch camera.state {
        case .starting, .running:
            ZStack {
                Image(systemName: "camera.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.18))
                if settled {
                    Viewfinder(session: camera.session)
                        .opacity(camera.state == .running ? 1 : 0)
                        .animation(.easeOut(duration: 0.4), value: camera.state)
                        .blur(radius: turning ? 26 : 0)
                        .scaleEffect(turning ? 1.06 : 1)
                        .transition(.opacity)
                }
            }
        case .denied:
            message("dadi can't use the camera.\nAllow it in Settings, or choose from your library.")
        case .unavailable(let reason):
            message(reason)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.75))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
    }

    private var grabber: some View {
        VStack {
            Capsule()
                .fill(.white.opacity(0.55))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(.rect)
                .onTapGesture(perform: close)
                .gesture(DragGesture(minimumDistance: 12).onEnded { if $0.translation.height > 50 { close() } })
                .accessibilityLabel("Close camera")
                .accessibilityAddTraits(.isButton)
            Spacer()
        }
        .opacity(arrived ? 1 : 0)
    }

    private var zoomLabel: some View {
        VStack {
            Text(String(format: "%.1f×", camera.zoom))
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.45), in: .capsule)
                .padding(.top, 52)
            Spacer()
        }
        .opacity(pinching ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: pinching)
        .allowsHitTesting(false)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Spacer()
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.5), in: .capsule)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            HStack {
                sideButton("photo.on.rectangle", label: "Choose from library") { libraryOpen = true }
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: take) {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 3.5)
                        Circle().fill(.white).padding(7).scaleEffect(taking ? 0.84 : 1)
                    }
                    .opacity(camera.state == .running ? 1 : 0.4)
                    .frame(width: Self.shutter, height: Self.shutter)
                    .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .disabled(camera.state != .running || taking)
                .accessibilityLabel("Take photo")
                sideButton(camera.torchOn ? "bolt.fill" : "bolt.slash.fill", label: camera.torchOn ? "Light off" : "Light on", lit: camera.torchOn, action: toggleTorch)
                    .opacity(camera.hasTorch ? 1 : 0.35)
                    .disabled(!camera.hasTorch)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .animation(Motion.snap, value: problem)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: taking)
    }

    private func sideButton(_ symbol: String, label: String, lit: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(lit ? Color.black : .white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.button, height: Self.button)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(lit ? .regular.tint(.white).interactive() : .regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !pinching {
                    pinching = true
                    zoomAtPinchStart = camera.zoom
                }
                attempt { try camera.setZoom(zoomAtPinchStart * value.magnification) }
            }
            .onEnded { _ in
                Task {
                    do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                    pinching = false
                }
            }
    }

    /// Turns to the other camera behind a soft blur that clears once it is live.
    private func turn() {
        guard camera.state == .running, !turning else { return }
        flips += 1
        Task {
            withAnimation(.easeIn(duration: 0.2)) { turning = true }
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            camera.flip()
            do { try await Task.sleep(for: .milliseconds(420)) } catch { return }
            withAnimation(.easeOut(duration: 0.4)) { turning = false }
        }
    }

    private func toggleTorch() {
        attempt { try camera.toggleTorch() }
    }

    private func attempt(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            problem = error.localizedDescription
        }
    }

    private func take() {
        guard count < DraftPhoto.limit else {
            problem = "A message holds up to \(DraftPhoto.limit) photos."
            return
        }
        problem = nil
        taking = true
        Task {
            defer { taking = false }
            do {
                add(try DraftPhoto(data: try await camera.capture()))
                shutter += 1
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    /// Adds the picked library items, as many as the message has room for.
    private func load(_ items: [PhotosPickerItem]) async {
        problem = nil
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    problem = "A photo couldn't be read from your library."
                    continue
                }
                add(try DraftPhoto(data: data))
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
