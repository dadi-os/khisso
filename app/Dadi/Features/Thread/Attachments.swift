import QuickLook
import SwiftUI
import UIKit

/// Where an attachment's bytes are kept on the phone once fetched from Hath: a
/// folder per attachment in the temporary directory, holding one file with
/// the attachment's own name, so QuickLook and Share show the real filename.
enum AttachmentFile {
    static let directory = URL.temporaryDirectory.appending(path: "attachments", directoryHint: .isDirectory)

    /// Where `file` is kept under `directory`.
    static func url(for file: AttachmentSummary, in directory: URL = directory) -> URL {
        directory
            .appending(path: name(file.id), directoryHint: .isDirectory)
            .appending(path: name(file.filename), directoryHint: .notDirectory)
    }

    /// `filename` as one path component: slashes and colons become dashes,
    /// and a name left empty or only dots is "attachment".
    static func name(_ filename: String) -> String {
        let cleaned = filename
            .replacing("/", with: "-")
            .replacing(":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.allSatisfy { $0 == "." } ? "attachment" : cleaned
    }

    /// `file` on the phone, fetched from Hath the first time it is asked for.
    static func local(_ file: AttachmentSummary, from hath: HathClient) async throws -> URL {
        let url = url(for: file)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return url }
        let data = try await hath.attachment(file.id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// The image at `url`, decoded for display; `maxPixels` bounds its longer
    /// side for a thumbnail, nil keeps its full size.
    static func image(at url: URL, maxPixels: CGFloat?) async throws -> UIImage {
        guard let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) else {
            throw AttachmentProblem(message: "\(url.lastPathComponent) isn't an image dadi can show.")
        }
        let prepared: UIImage?
        if let maxPixels {
            let longer = max(image.size.width * image.scale, image.size.height * image.scale)
            let ratio = min(1, maxPixels / max(longer, 1))
            prepared = await image.byPreparingThumbnail(ofSize: CGSize(width: image.size.width * image.scale * ratio, height: image.size.height * image.scale * ratio))
        } else {
            prepared = await image.byPreparingForDisplay()
        }
        guard let prepared else {
            throw AttachmentProblem(message: "\(url.lastPathComponent) couldn't be decoded.")
        }
        return prepared
    }
}

/// An attachment that could not be shown.
struct AttachmentProblem: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

/// Image thumbnails already decoded, so a message scrolling back into view
/// does not decode its images again.
@MainActor
private enum Thumbnails {
    static let cache = NSCache<NSString, UIImage>()
}

/// One attachment in a thread. An image shows inline as a thumbnail and opens
/// full screen to zoom and share; any other file is a row that opens in
/// QuickLook. Bytes come from Hath over the app's own session; while they
/// load the row shows progress, and a failure shows its reason and retries on
/// the next tap.
struct AttachmentView: View {
    let file: AttachmentSummary
    let hath: HathClient

    @State private var thumbnail: UIImage?
    @State private var loading = false
    @State private var problem: String?
    @State private var viewing: ViewedImage?
    @State private var preview: URL?

    /// The longest side of a thumbnail, in points.
    private let thumbnailSide: CGFloat = 240

    private var isImage: Bool { file.mediaType.hasPrefix("image/") }

    var body: some View {
        Button(action: open) {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: thumbnailSide, maxHeight: thumbnailSide)
                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.rule))
                    .overlay {
                        if loading {
                            ProgressView().tint(.bone).padding(10).glassEffect(.regular, in: .circle)
                        }
                    }
                    .transition(.opacity)
            } else {
                row
            }
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .animation(Motion.settle, value: thumbnail)
        .animation(Motion.snap, value: problem)
        .accessibilityLabel(file.description.map { "\(file.filename), \($0)" } ?? file.filename)
        .accessibilityHint(isImage ? "Opens the image" : "Opens the file")
        .task(id: file.id) {
            guard isImage else { return }
            await loadThumbnail()
        }
        .quickLookPreview($preview)
        .fullScreenCover(item: $viewing) { viewed in
            ImageViewer(image: viewed.image, file: viewed.url, title: file.filename)
        }
    }

    private var row: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(file.filename).font(.footnote.weight(.medium)).foregroundStyle(.ink).lineLimit(1)
                if let problem {
                    Text(problem)
                        .font(.caption2)
                        .foregroundStyle(.danger)
                        .lineLimit(3)
                } else {
                    Text(file.description ?? ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.inkMuted)
                        .lineLimit(2)
                }
            }
        } icon: {
            ZStack {
                if loading {
                    ProgressView().controlSize(.small).tint(.sageDeep)
                } else {
                    Image(systemName: problem != nil ? "exclamationmark.circle" : (isImage ? "photo" : "doc"))
                        .foregroundStyle(problem != nil ? .danger : .sageDeep)
                }
            }
            .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.boneRaised, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.rule))
        .contentShape(.rect(cornerRadius: 14))
    }

    private func loadThumbnail() async {
        if let cached = Thumbnails.cache.object(forKey: file.id as NSString) {
            thumbnail = cached
            return
        }
        loading = true
        defer { loading = false }
        do {
            let url = try await AttachmentFile.local(file, from: hath)
            let image = try await AttachmentFile.image(at: url, maxPixels: thumbnailSide * 3)
            Thumbnails.cache.setObject(image, forKey: file.id as NSString)
            thumbnail = image
            problem = nil
        } catch is CancellationError {
            return
        } catch {
            problem = error.localizedDescription
        }
    }

    private func open() {
        loading = true
        problem = nil
        Task {
            defer { loading = false }
            do {
                let url = try await AttachmentFile.local(file, from: hath)
                if isImage {
                    viewing = ViewedImage(id: file.id, image: try await AttachmentFile.image(at: url, maxPixels: nil), url: url)
                } else {
                    preview = url
                }
            } catch is CancellationError {
                return
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}

/// An image opened full screen, with the file it came from for sharing.
private struct ViewedImage: Identifiable {
    let id: String
    let image: UIImage
    let url: URL
}

/// An image full screen on black: pinch or double-tap to zoom, drag to look
/// around once zoomed, drag down to close, and share the original file.
private struct ImageViewer: View {
    let image: UIImage
    let file: URL
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var zoomAtStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var offsetAtStart: CGSize = .zero

    /// How far down a drag at full size goes before it closes the viewer.
    private let closeDistance: CGFloat = 120
    private let maxZoom: CGFloat = 5

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(zoom)
                    .offset(offset)
                    .contentShape(.rect)
                    .gesture(magnify(in: proxy.size).simultaneously(with: pan(in: proxy.size)))
                    .onTapGesture(count: 2) {
                        withAnimation(Motion.snap) {
                            zoom = zoom > 1 ? 1 : 2.5
                            zoomAtStart = zoom
                            offset = .zero
                            offsetAtStart = .zero
                        }
                    }
            }
            .background(.black.opacity(zoom > 1 ? 1 : 1 - min(0.6, abs(offset.height) / (closeDistance * 3))))
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: file)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(.clear)
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(maxZoom, max(0.8, zoomAtStart * value.magnification))
            }
            .onEnded { _ in
                withAnimation(Motion.snap) {
                    zoom = min(maxZoom, max(1, zoom))
                    if zoom == 1 { offset = .zero }
                    offset = clamped(offset, in: size)
                    zoomAtStart = zoom
                    offsetAtStart = offset
                }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if zoomAtStart > 1 {
                    offset = CGSize(width: offsetAtStart.width + value.translation.width, height: offsetAtStart.height + value.translation.height)
                } else {
                    offset = CGSize(width: 0, height: max(0, value.translation.height))
                }
            }
            .onEnded { value in
                if zoomAtStart <= 1 && value.translation.height > closeDistance {
                    dismiss()
                    return
                }
                withAnimation(Motion.snap) {
                    offset = zoomAtStart > 1 ? clamped(offset, in: size) : .zero
                    offsetAtStart = offset
                }
            }
    }

    /// `offset` kept within how far the zoomed image overhangs `size`.
    private func clamped(_ offset: CGSize, in size: CGSize) -> CGSize {
        let reachX = size.width * (zoom - 1) / 2
        let reachY = size.height * (zoom - 1) / 2
        return CGSize(width: min(reachX, max(-reachX, offset.width)), height: min(reachY, max(-reachY, offset.height)))
    }
}
