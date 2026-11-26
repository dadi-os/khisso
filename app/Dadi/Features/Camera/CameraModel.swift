import AVFoundation
import Observation

/// The device's camera for the composer's viewfinder: asks permission once,
/// runs a capture session while the viewfinder is up, flips between the back
/// and front cameras and takes one photo at a time. It is `running` only once
/// the session is delivering frames. Every call into the capture session, set
/// up, start and stop, happens on a serial queue so the main actor never waits
/// on camera hardware, and the session stops as soon as the viewfinder closes.
@MainActor
@Observable
final class CameraModel: NSObject, AVCapturePhotoCaptureDelegate {
    enum State: Equatable {
        case starting
        case running
        case denied
        case unavailable(String)
    }

    /// The capture objects and the queue that owns them. They are only touched
    /// on `queue`, except where noted; AVFoundation does not make them Sendable.
    private final class Rig: @unchecked Sendable {
        let queue = DispatchQueue(label: "dadi.camera", qos: .userInitiated)
        let session = AVCaptureSession()
        let output = AVCapturePhotoOutput()
        /// Read on the main actor once set up, for the light and zoom, which AVFoundation allows from any thread.
        var device: AVCaptureDevice?

        /// Connects the camera at `position` to the session and returns the device zoom at which the main camera fills the view.
        func configure(position: AVCaptureDevice.Position) throws -> CGFloat {
            let types: [AVCaptureDevice.DeviceType] = position == .back
                ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
                : [.builtInWideAngleCamera]
            guard let device = types.lazy.compactMap({ AVCaptureDevice.default($0, for: .video, position: position) }).first else {
                throw PhotoProblem(message: "This device has no \(position == .back ? "back" : "front") camera.")
            }
            let input = try AVCaptureDeviceInput(device: device)
            let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
            let mainZoom = hasUltraWide ? (device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 1) : 1
            try device.lockForConfiguration()
            device.videoZoomFactor = mainZoom
            device.unlockForConfiguration()
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
            self.device = device
            return mainZoom
        }
    }

    private(set) var state = State.starting
    private(set) var torchOn = false
    /// How far the preview is zoomed, as times the main camera's view: 1 is
    /// the main camera, below 1 the ultra wide.
    private(set) var zoom: CGFloat = 1

    /// Made on first use: a view owning a model builds it on every redraw, and most never open the camera.
    @ObservationIgnored private lazy var rig = Rig()
    /// The device's own zoom factor at which the main (wide) camera fills the
    /// view: above 1 on a phone with an ultra wide, whose view is zoom 1.
    @ObservationIgnored private var mainZoom: CGFloat = 1
    @ObservationIgnored private var position = AVCaptureDevice.Position.back
    @ObservationIgnored private var pending: CheckedContinuation<Data, Error>?
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var setup: Task<Void, Never>?
    /// True from `start` until `release`, so a start that finishes after the viewfinder closed does not report running.
    @ObservationIgnored private var wanted = false

    /// The session the viewfinder's preview layer shows.
    var session: AVCaptureSession { rig.session }

    /// Sets the session up ahead of the viewfinder when access is already
    /// granted, so choosing the camera is quick. Never asks for access, never
    /// starts the camera, and does its work off the main actor.
    func prepare() async {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        await ensureConfigured()
    }

    /// Asks for camera access if it has not been asked, then starts the session.
    func start() async {
        wanted = true
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
        await ensureConfigured()
        guard configured, wanted else { return }
        let rig = rig
        await withCheckedContinuation { continuation in
            rig.queue.async {
                if !rig.session.isRunning { rig.session.startRunning() }
                continuation.resume()
            }
        }
        if wanted { state = .running }
    }

    /// The viewfinder has closed: the light goes off and the session stops now.
    func release() {
        wanted = false
        if torchOn {
            do { try toggleTorch() } catch { state = .unavailable(error.localizedDescription) }
        }
        let rig = rig
        rig.queue.async { rig.session.stopRunning() }
        if state == .running { state = .starting }
    }

    /// True when the camera in use has a light, which the front one does not.
    var hasTorch: Bool { rig.device?.hasTorch ?? false }

    /// Turns the camera's light on or off.
    func toggleTorch() throws {
        guard let device = rig.device, device.hasTorch else { throw PhotoProblem(message: "This camera has no light.") }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.torchMode = torchOn ? .off : .on
        torchOn.toggle()
    }

    /// Zooms the preview to `factor` times the main camera's view, so 0.5 is
    /// the ultra wide and the top is as far as the camera can go.
    func setZoom(_ factor: CGFloat) throws {
        guard let device = rig.device else { return }
        let raw = min(max(factor * mainZoom, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.videoZoomFactor = raw
        zoom = raw / mainZoom
    }

    /// Switches between the back and front cameras.
    func flip() async {
        position = position == .back ? .front : .back
        configured = false
        await ensureConfigured()
    }

    /// Takes a photo and returns its JPEG or HEIC bytes.
    func capture() async throws -> Data {
        guard pending == nil else { throw PhotoProblem(message: "A photo is already being taken.") }
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .speed
            rig.output.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Connects the camera once, however many callers ask at the same time.
    private func ensureConfigured() async {
        if let setup {
            await setup.value
            return
        }
        guard !configured else { return }
        let task = Task {
            let rig = rig
            let position = position
            do {
                let zoomed = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGFloat, Error>) in
                    rig.queue.async { continuation.resume(with: Result { try rig.configure(position: position) }) }
                }
                mainZoom = zoomed
                torchOn = false
                zoom = 1
                configured = true
            } catch {
                configured = false
                state = .unavailable(error.localizedDescription)
            }
        }
        setup = task
        await task.value
        setup = nil
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
