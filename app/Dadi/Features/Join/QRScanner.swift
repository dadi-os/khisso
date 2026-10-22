import AVFoundation
import SwiftUI
import VisionKit

/// The live camera that reads the setup QR code the box shows in Preferences →
/// Devices. `onScan` gets each new QR payload once; scanning keeps running so a
/// rejected code can be replaced by pointing at the right one. `onFail` gets
/// the reason the camera stopped.
struct QRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onFail: (String) -> Void

    /// Why the scanner cannot run on this device right now, or nil when it can.
    @MainActor
    static var unavailableReason: String? {
        if !DataScannerViewController.isSupported {
            return "This iPhone can't scan codes."
        }
        if !DataScannerViewController.isAvailable {
            return "dadi needs the camera to scan your box's code. Allow it in Settings → dadi → Camera."
        }
        return nil
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !scanner.isScanning else { return }
        do {
            try scanner.startScanning()
        } catch {
            onFail(error.localizedDescription)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onFail: onFail) }

    /// Receives recognized codes and hands each new payload to `onScan`.
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        let onFail: (String) -> Void
        private var last: String?

        init(onScan: @escaping (String) -> Void, onFail: @escaping (String) -> Void) {
            self.onScan = onScan
            self.onFail = onFail
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue, payload != last else { continue }
                last = payload
                onScan(payload)
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onFail("The camera stopped: \(error.localizedDescription)")
        }
    }
}

/// The camera's flashlight, which the scanner does not offer itself. It
/// drives the same back camera the scanner reads with.
enum Torch {
    /// Why the torch would not change.
    struct Refused: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static var available: Bool { AVCaptureDevice.default(for: .video)?.hasTorch == true }

    static func set(_ on: Bool) throws {
        guard let camera = AVCaptureDevice.default(for: .video), camera.hasTorch else {
            throw Refused(message: "This iPhone has no flashlight.")
        }
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }
        if on {
            try camera.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
        } else {
            camera.torchMode = .off
        }
    }
}
