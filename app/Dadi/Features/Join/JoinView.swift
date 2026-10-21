import SwiftUI
#if os(iOS)
import AVFoundation
#endif

/// First run: join dadi with the setup code from dadiOS Preferences → Devices.
/// The iPhone opens on the camera to scan the box's QR code, with pasting the
/// code as the alternative; the Mac pastes. The first join has to happen on the
/// box's network, where Headscale answers.
struct JoinView: View {
    let connection: Connection

    #if os(iOS)
    /// Nil until camera access is settled, then whether the paste form shows.
    @State private var pasting: Bool?
    #else
    private let pasting = true
    #endif
    @State private var code = ""
    @State private var problem: String?

    var body: some View {
        #if os(iOS)
        Group {
            switch pasting {
            case nil:
                Color.black.ignoresSafeArea()
            case true?:
                pasteForm
            case false?:
                scanner
            }
        }
        .task {
            guard pasting == nil else { return }
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            pasting = QRScanner.unavailableReason != nil
        }
        #else
        pasteForm
        #endif
    }

    /// Joins with a scanned or pasted code, or shows why it was rejected.
    private func join(_ text: String) {
        do {
            try connection.join(pasted: text)
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    #if os(iOS)
    private var scanner: some View {
        ZStack {
            QRScanner(onScan: join, onFail: { problem = $0 })
                .ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.65), .clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 18) {
                Text("દાદી")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white)
                Text("Scan the code on your box")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 4, dash: [18, 12]))
                    .frame(width: 260, height: 260)
                    .shadow(color: .black.opacity(0.4), radius: 12)
                    .allowsHitTesting(false)
                Spacer()
                Text("Preferences → Devices on your box shows it. Be on the box's network for this first join.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                if let problem {
                    Text(problem)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.tint(.red.opacity(0.5)), in: .rect(cornerRadius: 14))
                        .frame(maxWidth: 340)
                }
                Button {
                    problem = nil
                    pasting = true
                } label: {
                    Label("Paste a setup code", systemImage: "doc.on.clipboard")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
        }
    }
    #endif

    private var pasteForm: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("દાદી")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Join dadi").font(.title2.weight(.semibold))
                Text("On your box, open Preferences → Devices, add this device, and paste its setup code here. Be on the same network as the box for this first join.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            TextField("Setup code", text: $code, axis: .vertical)
                .lineLimit(3...6)
                .font(.callout.monospaced())
                .textFieldStyle(.plain)
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .frame(maxWidth: 460)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            Button("Join") { join(code) }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #if os(iOS)
            if let reason = QRScanner.unavailableReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            } else {
                Button {
                    problem = nil
                    pasting = false
                } label: {
                    Label("Scan the code instead", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.glass)
            }
            #endif
            Spacer()
        }
        .padding(24)
    }
}
