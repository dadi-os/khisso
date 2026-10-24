import AVFoundation
import CoreMedia
import SwiftUI
import UIKit

/// Draws decoded-on-display H.264 frames: the display layer decodes the
/// length-prefixed frames the splitter produces.
@MainActor
final class FrameRenderer {
    let layer = AVSampleBufferDisplayLayer()
    private var format: CMVideoFormatDescription?
    private var awaitingKey = true
    private var frames: Int64 = 0

    init() {
        layer.videoGravity = .resizeAspect
    }

    /// Starts decoding with a new SPS and PPS; the next key frame begins it.
    func configure(sps: Data, pps: Data) throws {
        var made: CMVideoFormatDescription?
        let status = sps.withUnsafeBytes { s in
            pps.withUnsafeBytes { p in
                let pointers = [s.bindMemory(to: UInt8.self).baseAddress!, p.bindMemory(to: UInt8.self).baseAddress!]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: pointers,
                    parameterSetSizes: [sps.count, pps.count],
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &made
                )
            }
        }
        guard status == noErr, let made else { throw BrowserProblem(message: "The browser's video settings were not understood (\(status)).") }
        format = made
        awaitingKey = true
    }

    /// Shows `frame`; frames before the first key frame are skipped.
    func show(_ frame: H264Frame) throws {
        guard let format, !awaitingKey || frame.key else { return }
        awaitingKey = false
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: frame.data.count, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: frame.data.count, flags: 0, blockBufferOut: &block
        )
        guard status == noErr, let block else { throw BrowserProblem(message: "A video frame could not be held (\(status)).") }
        status = frame.data.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: frame.data.count)
        }
        guard status == noErr else { throw BrowserProblem(message: "A video frame could not be copied (\(status)).") }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: frames, timescale: 30), decodeTimeStamp: .invalid)
        var size = frame.data.count
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample
        )
        guard status == noErr, let sample else { throw BrowserProblem(message: "A video frame could not be built (\(status)).") }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        frames += 1
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed {
            renderer.flush()
            awaitingKey = true
            throw BrowserProblem(message: renderer.error?.localizedDescription ?? "The display stopped.")
        }
        renderer.enqueue(sample)
    }
}

/// A browser stream that could not be shown.
struct BrowserProblem: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

/// A UIView that keeps the renderer's display layer the size of the view as
/// it is laid out.
private final class DisplayLayerHost: UIView {
    var renderer: FrameRenderer? {
        didSet {
            oldValue?.layer.removeFromSuperlayer()
            if let layer = renderer?.layer { self.layer.addSublayer(layer) }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderer?.layer.frame = bounds
    }
}

private struct DisplayLayerView: UIViewRepresentable {
    let renderer: FrameRenderer

    func makeUIView(context: Context) -> DisplayLayerHost {
        let host = DisplayLayerHost()
        host.renderer = renderer
        return host
    }

    func updateUIView(_ host: DisplayLayerHost, context: Context) {}
}

/// The live display of an agent's browser from Nas, 16:9, watching only. It
/// streams while on screen and the app is forward; a stream that drops or
/// goes quiet reconnects on a short bounded backoff, keeping the last frame
/// under a badge, and fails with its last error and a Retry once those run out.
struct BrowserView: View {
    let nas: NasClient
    let browserId: Int

    private enum Phase: Equatable {
        case opening
        case live
        case retrying(String)
        case failed(String)
    }

    /// Waits before each reconnect after a drop; a received frame starts over.
    private static let retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8)]

    @State private var renderer = FrameRenderer()
    @State private var phase = Phase.opening
    @State private var attempt = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.sage.opacity(0.1)
            DisplayLayerView(renderer: renderer)
                .opacity(phase == .opening ? 0 : 1)
            switch phase {
            case .opening:
                Text("Browser \(browserId)")
                    .font(.caption)
                    .foregroundStyle(.inkFaint)
            case .live:
                EmptyView()
            case .retrying:
                Text("reconnecting…")
                    .font(.caption2)
                    .foregroundStyle(.inkMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(8)
            case .failed(let error):
                VStack(spacing: 8) {
                    Text("Browser \(browserId) stream failed: \(error)")
                        .font(.caption)
                        .foregroundStyle(.danger)
                        .multilineTextAlignment(.center)
                    Button("Retry") { attempt += 1 }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
                .padding(12)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.sageLine.opacity(0.7), lineWidth: 1))
        .animation(Motion.settle, value: phase)
        .task(id: StreamKey(browserId: browserId, forward: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active else { return }
            await watch()
        }
    }

    private struct StreamKey: Hashable {
        let browserId: Int
        let forward: Bool
        let attempt: Int
    }

    /// Streams until cancelled, reconnecting after drops; fails once the
    /// retries run out without a frame in between.
    private func watch() async {
        var retry = 0
        phase = .opening
        while !Task.isCancelled {
            let failure: String
            do {
                for try await event in Self.events(from: try await nas.browserStream(browserId)) {
                    switch event {
                    case .config(let sps, let pps):
                        try renderer.configure(sps: sps, pps: pps)
                    case .frame(let frame):
                        try renderer.show(frame)
                        retry = 0
                        if phase != .live { phase = .live }
                    }
                }
                failure = "Nas ended the stream"
            } catch is CancellationError {
                return
            } catch let error as ServiceError where error.status == 404 {
                phase = .failed("browser \(browserId) is not running")
                return
            } catch {
                failure = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            guard retry < Self.retryDelays.count else {
                phase = .failed(failure)
                return
            }
            phase = .retrying(failure)
            do { try await Task.sleep(for: Self.retryDelays[retry]) } catch { return }
            retry += 1
        }
    }

    /// `bytes` split into H.264 events off the main thread, so only frames
    /// reach it.
    private nonisolated static func events(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<H264Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var splitter = H264Splitter()
                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        guard buffer.count >= 1024 else { continue }
                        for event in splitter.push(buffer) { continuation.yield(event) }
                        buffer.removeAll(keepingCapacity: true)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
