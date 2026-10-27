import AVFoundation
import Observation

/// The device's camera for the composer's viewfinder: asks permission once,
/// runs a capture session while the viewfinder is up, flips between the back
/// and front cameras and takes one photo at a time. It is `running` only once
/// the session is delivering frames. The composer prepares the session ahead,
/// when access is already granted, and the session lingers briefly after the
/// viewfinder closes, so opening it is quick.
@MainActor
@Observable
final class CameraModel: NSObject, AVCapturePhotoCaptureDelegate {
    enum State: Equatable {
        case starting
        case running
        case denied
        case unavailable(String)
    }

    /// AVCaptureSession is not Sendable; it is only started and stopped off
    /// the main thread, as Apple advises.
    private final class Session: @unchecked Sendable {
        let session = AVCaptureSession()
    }

    private(set) var state = State.starting
    private(set) var torchOn = false
    /// How far the preview is zoomed, as times the main camera's view: 1 is
    /// the main camera, below 1 the ultra wide.
    private(set) var zoom: CGFloat = 1

    @ObservationIgnored private let box = Session()
    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private var device: AVCaptureDevice?
    /// The device's own zoom factor at which the main (wide) camera fills the
    /// view: above 1 on a phone with an ultra wide, whose view is zoom 1.
    @ObservationIgnored private var mainZoom: CGFloat = 1
    @ObservationIgnored private var position = AVCaptureDevice.Position.back
    @ObservationIgnored private var pending: CheckedContinuation<Data, Error>?

    /// The session the viewfinder's preview layer shows.
    var session: AVCaptureSession { box.session }

    /// How long the session keeps running after the viewfinder closes.
    private static let linger: Duration = .seconds(20)

    @ObservationIgnored private var configured = false
    @ObservationIgnored private var stopping: Task<Void, Never>?

    /// Sets the session up ahead of the viewfinder when access is already
    /// granted; never asks for it.
    func prepare() async {
        guard !configured, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        configureOrFail()
    }

    /// Starts the session ahead of the viewfinder when access is already
    /// granted, so choosing the camera opens on a live picture; it stops again
    /// after a while if the camera is not chosen. Never asks for access.
    func warm() async {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        await start()
        release()
    }

    /// Asks for camera access if it has not been asked, then starts the session.
    func start() async {
        stopping?.cancel()
        stopping = nil
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }
        if !configured { configureOrFail() }
        guard configured else { return }
        if box.session.isRunning {
            state = .running
            return
        }
        let running = box
        DispatchQueue.global(qos: .userInitiated).async {
            running.session.startRunning()
            Task { @MainActor in self.state = .running }
        }
    }

    /// The viewfinder has closed: the session stops after a short while,
    /// unless it is opened again first.
    func release() {
        if torchOn {
            do { try toggleTorch() } catch { state = .unavailable(error.localizedDescription) }
        }
        stopping?.cancel()
        stopping = Task {
            do { try await Task.sleep(for: Self.linger) } catch { return }
            let running = box
            DispatchQueue.global(qos: .userInitiated).async { running.session.stopRunning() }
            state = .starting
        }
    }

    /// True when the camera in use has a light, which the front one does not.
    var hasTorch: Bool { device?.hasTorch ?? false }

    /// Turns the camera's light on or off.
    func toggleTorch() throws {
        guard let device, device.hasTorch else { throw PhotoProblem(message: "This camera has no light.") }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.torchMode = torchOn ? .off : .on
        torchOn.toggle()
    }

    /// Zooms the preview to `factor` times the main camera's view, so 0.5 is
    /// the ultra wide and the top is as far as the camera can go.
    func setZoom(_ factor: CGFloat) throws {
        guard let device else { return }
        let raw = min(max(factor * mainZoom, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.videoZoomFactor = raw
        zoom = raw / mainZoom
    }

    /// Switches between the back and front cameras.
    func flip() {
        position = position == .back ? .front : .back
        configureOrFail()
    }

    /// Takes a photo and returns its JPEG or HEIC bytes.
    func capture() async throws -> Data {
        guard pending == nil else { throw PhotoProblem(message: "A photo is already being taken.") }
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    private func configureOrFail() {
        do {
            try configure()
            configured = true
        } catch {
            configured = false
            state = .unavailable(error.localizedDescription)
        }
    }

    private func configure() throws {
        let position = self.position
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        guard let device = types.lazy.compactMap({ AVCaptureDevice.default($0, for: .video, position: position) }).first else {
            throw PhotoProblem(message: "This device has no \(position == .back ? "back" : "front") camera.")
        }
        let input = try AVCaptureDeviceInput(device: device)
        self.device = device
        torchOn = false
        zoom = 1
        let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        mainZoom = hasUltraWide ? (device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 1) : 1
        try device.lockForConfiguration()
        device.videoZoomFactor = mainZoom
        device.unlockForConfiguration()
        let session = box.session
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for existing in session.inputs { session.removeInput(existing) }
        session.sessionPreset = .photo
        guard session.canAddInput(input) else { throw PhotoProblem(message: "The camera can't be used right now.") }
        session.addInput(input)
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else { throw PhotoProblem(message: "The camera can't take photos right now.") }
            session.addOutput(output)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            defer { pending = nil }
            if let error {
                pending?.resume(throwing: error)
            } else if let data {
                pending?.resume(returning: data)
            } else {
                pending?.resume(throwing: PhotoProblem(message: "The camera returned no photo."))
            }
        }
    }
}
