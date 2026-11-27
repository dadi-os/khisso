import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Where a staged file stands on its way to the box.
enum UploadState: Equatable {
    case pending
    case uploading
    /// On the box at `path`, which Nas answered, so a renamed copy is honoured.
    case uploaded(path: String)
    case failed(String)
}

/// A photo or file waiting in the composer to go with the next message. It sits in a temporary copy until it is uploaded
/// to the month's Inbox; the message then carries its `box://` link.
struct DraftFile: Identifiable, Equatable {
    /// Most files one message stages.
    static let limit = 8

    /// The longer side, in pixels, a photo is shrunk to.
    private static let maxPixels: CGFloat = 2048
    private static let quality: CGFloat = 0.8

    let id: UUID
    /// The name it is uploaded under.
    let name: String
    let mediaType: String
    /// The temporary copy, in a folder of its own named by `id`.
    let url: URL
    /// An image's preview; nil for any other file.
    let thumbnail: UIImage?
    var upload = UploadState.pending

    init(id: UUID = UUID(), name: String, mediaType: String, url: URL, thumbnail: UIImage? = nil) {
        self.id = id
        self.name = name
        self.mediaType = mediaType
        self.url = url
        self.thumbnail = thumbnail
    }

    /// A photo from the bytes of any image the system can read, shrunk and re-encoded as JPEG so it stays small over the
    /// mesh. A camera frame is many megapixels, so this runs off the main actor.
    nonisolated static func photo(data: Data) async throws -> DraftFile {
        guard let image = UIImage(data: data) else {
            throw PhotoProblem(message: "That file isn't an image dadi can read.")
        }
        let longer = max(image.size.width, image.size.height) * image.scale
        let ratio = min(1, maxPixels / max(longer, 1))
        let size = CGSize(width: image.size.width * image.scale * ratio, height: image.size.height * image.scale * ratio)
        guard let shrunk = await image.byPreparingThumbnail(ofSize: size),
              let encoded = shrunk.jpegData(compressionQuality: quality),
              let thumbnail = await shrunk.byPreparingThumbnail(ofSize: CGSize(width: 240, height: 240 * size.height / size.width))
        else {
            throw PhotoProblem(message: "That image couldn't be prepared.")
        }
        let id = UUID()
        let name = "photo-\(id.uuidString.prefix(8).lowercased()).jpg"
        let url = try copy(to: id, named: name) { try encoded.write(to: $0) }
        return DraftFile(id: id, name: name, mediaType: "image/jpeg", url: url, thumbnail: thumbnail)
    }

    /// A photo from an item picked in the photo library.
    static func picked(_ item: PhotosPickerItem) async throws -> DraftFile {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw PhotoProblem(message: "A photo couldn't be read from your library.")
        }
        return try await photo(data: data)
    }

    /// A file chosen in the document picker, copied out of its security scope under its own name. An image gets a preview.
    static func document(at source: URL) throws -> DraftFile {
        guard source.startAccessingSecurityScopedResource() else {
            throw PhotoProblem(message: "\(source.lastPathComponent) can't be read.")
        }
        defer { source.stopAccessingSecurityScopedResource() }
        let id = UUID()
        let name = source.lastPathComponent
        let url = try copy(to: id, named: name) { try FileManager.default.copyItem(at: source, to: $0) }
        let type = UTType(filenameExtension: url.pathExtension)
        let thumbnail = type?.conforms(to: .image) == true ? UIImage(contentsOfFile: url.path(percentEncoded: false))?.preparingThumbnail(of: CGSize(width: 240, height: 240)) : nil
        return DraftFile(id: id, name: name, mediaType: type?.preferredMIMEType ?? "application/octet-stream", url: url, thumbnail: thumbnail)
    }

    private nonisolated static func copy(to id: UUID, named name: String, write: (URL) throws -> Void) throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "drafts/\(id.uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name, directoryHint: .notDirectory)
        try write(url)
        return url
    }

    /// Removes the temporary copy.
    func discard() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

extension Array where Element == DraftFile {
    /// Records `state` on the file with `id`.
    mutating func setUpload(_ id: UUID, _ state: UploadState) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].upload = state
    }
}

/// A photo or file that could not be added.
struct PhotoProblem: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
