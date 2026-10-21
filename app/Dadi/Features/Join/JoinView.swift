import SwiftUI
#if os(iOS)
import AVFoundation
#endif

/// First run: join dadi with the setup code from dadiOS Preferences → Devices.
/// The iPhone opens with the દાદી wordmark resolving on the field, which rises
/// as the camera fades in to scan the box's QR code; pasting the code is the
/// alternative. The Mac pastes on a glass card. The first join has to happen on
/// the box's network, where Headscale answers.
struct JoinView: View {
    let connection: Connection
    let wordmark: Namespace.ID

    /// Where the Join screen is in its sequence.
    private enum Stage: Equatable {
        /// The wordmark resolving before the camera opens.
        case intro
        case scanning
        /// A valid code was read; the reticle celebrates before joining.
        case accepted
        case pasting
    }

    @State private var stage: Stage = .intro
    @State private var code = ""
    @State private var problem: String?
    @State private var accepted = 0

    var body: some View {
        ZStack {
            FieldBloom()
            #if os(iOS)
            if stage == .scanning || stage == .accepted {
                scanner.transition(.opacity.animation(.easeOut(duration: 0.9)))
            }
            #endif
            content
        }
        .sensoryFeedback(.success, trigger: accepted)
        #if os(iOS)
        .task { await openCamera() }
        #else
        .onAppear { stage = .pasting }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .intro:
            VStack {
                Spacer()
                ResolvingWordmark(size: 96)
                    .matchedGeometryEffect(id: "wordmark", in: wordmark)
                Spacer()
            }
        case .scanning, .accepted:
            #if os(iOS)
            scannerChrome
            #endif
        case .pasting:
            pasteCard
        }
    }

    /// Validates a scanned or pasted code, celebrates, then joins with it.
    private func accept(_ text: String) {
        do {
            _ = try SetupCode(pasted: text)
        } catch {
            withAnimation(Motion.snap) { problem = error.localizedDescription }
            return
        }
        problem = nil
        accepted += 1
        let scanned = stage != .pasting
        withAnimation(Motion.pop) { if scanned { stage = .accepted } }
        Task {
            do {
                try await Task.sleep(for: .milliseconds(scanned ? 850 : 250))
                try connection.join(pasted: text)
            } catch {
                withAnimation(Motion.snap) {
                    problem = error.localizedDescription
                    stage = stage == .accepted ? .scanning : stage
                }
            }
        }
    }

    #if os(iOS)
    /// Lets the wordmark resolve, asks for the camera if it has never been
    /// asked, then opens the scanner or, without a camera, the paste card.
    private func openCamera() async {
        guard stage == .intro else { return }
        let start = ContinuousClock.now
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        do {
            try await Task.sleep(until: start + .milliseconds(1500))
        } catch {
            return
        }
        withAnimation(Motion.settle) {
            stage = QRScanner.unavailableReason == nil ? .scanning : .pasting
        }
    }

    private var scanner: some View {
        QRScanner(onScan: accept, onFail: { reason in withAnimation(Motion.snap) { problem = reason } })
            .ignoresSafeArea()
            .overlay {
                LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0.1), .black.opacity(0.15), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
    }

    private var scannerChrome: some View {
        VStack(spacing: 0) {
            Text("દાદી")
                .font(.wordmark(40))
                .inkCentered(.word, size: 40)
                .foregroundStyle(.white)
                .matchedGeometryEffect(id: "wordmark", in: wordmark)
                .padding(.top, 8)
            Text(stage == .accepted ? "Got it" : "Scan the code on your box")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))
                .contentTransition(.opacity)
                .padding(.top, 6)
            Spacer()
            Reticle(accepted: stage == .accepted)
            Spacer()
            VStack(spacing: 14) {
                if let problem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassEffect(.regular.tint(.danger.opacity(0.55)), in: .rect(cornerRadius: 16))
                        .frame(maxWidth: 340)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Text("In Preferences → Devices, add this iPhone. Stay on the box's network for this first join.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                        .transition(.opacity)
                }
                Button {
                    withAnimation(Motion.settle) {
                        problem = nil
                        stage = .pasting
                    }
                } label: {
                    Label("Paste a setup code", systemImage: "doc.on.clipboard")
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(stage == .accepted)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
    }
    #endif

    private var pasteCard: some View {
        VStack(spacing: 22) {
            Text("દાદી")
                .font(.wordmark(72))
                .inkCentered(.word, size: 72)
                .foregroundStyle(.sageDeep)
                .matchedGeometryEffect(id: "wordmark", in: wordmark)
            VStack(spacing: 8) {
                Text("Join dadi")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.ink)
                Text("On your box, open Preferences → Devices, add this device, and paste its setup code here. Stay on the box's network for this first join.")
                    .font(.callout)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            TextField("Setup code", text: $code, axis: .vertical)
                .lineLimit(3...6)
                .font(.callout.monospaced())
                .foregroundStyle(.ink)
                .textFieldStyle(.plain)
                .padding(16)
                .background(.boneRaised.opacity(0.7), in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.sageLine.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.danger)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            Button {
                accept(code)
            } label: {
                Text("Join").font(.body.weight(.semibold)).frame(minWidth: 140)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #if os(iOS)
            if let reason = QRScanner.unavailableReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.center)
            } else {
                Button {
                    withAnimation(Motion.settle) {
                        problem = nil
                        stage = .scanning
                    }
                } label: {
                    Label("Scan the code instead", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.glass)
            }
            #endif
        }
        .padding(32)
        .frame(maxWidth: 520)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(24)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

/// દાદી resolving one cluster at a time out of a soft blur.
struct ResolvingWordmark: View {
    let size: CGFloat
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let clusters = ["દા", "દી"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(clusters.enumerated()), id: \.offset) { index, cluster in
                Text(cluster)
                    .font(.wordmark(size))
                    .foregroundStyle(.sageDeep)
                    .opacity(shown ? 1 : 0)
                    .blur(radius: shown ? 0 : 14)
                    .scaleEffect(shown ? 1 : 0.86, anchor: .bottom)
                    .offset(y: shown ? 0 : 10)
                    .animation(reduceMotion ? .none : .smooth(duration: 0.9).delay(0.15 + Double(index) * 0.22), value: shown)
            }
        }
        .inkCentered(.word, size: size)
        .accessibilityLabel("dadi")
        .onAppear { shown = true }
    }
}

#if os(iOS)
/// The scanner's frame: dashes in dadi's sage march slowly around a breathing
/// square; an accepted code turns it solid and fills it with a check.
private struct Reticle: View {
    let accepted: Bool

    @State private var phase: CGFloat = 0
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(.sage.opacity(accepted ? 0.35 : 0))
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .strokeBorder(accepted ? Color.sageLine : .sageLine.opacity(0.95), style: StrokeStyle(lineWidth: accepted ? 6 : 4, lineCap: .round, dash: accepted ? [] : [20, 14], dashPhase: phase))
                .shadow(color: .black.opacity(0.35), radius: 14)
            Image(systemName: "checkmark")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(accepted ? 1 : 0)
                .scaleEffect(accepted ? 1 : 0.4)
                .symbolEffect(.bounce, value: accepted)
        }
        .frame(width: 264, height: 264)
        .scaleEffect(accepted ? 1.04 : (breathe ? 1.015 : 0.985))
        .animation(Motion.pop, value: accepted)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { phase = -68 }
            withAnimation(Motion.breath) { breathe = true }
        }
        .accessibilityHidden(true)
    }
}
#endif
