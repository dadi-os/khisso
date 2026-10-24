import UIKit

/// A photo waiting in the composer to go with the next message: shrunk and
/// re-encoded as JPEG so a message stays small over the mesh.
struct DraftPhoto: Identifiable, Equatable {
    /// Most photos one message carries, Hath's limit.
    static let limit = 8

    /// The longer side, in pixels, a photo is shrunk to.
    private static let maxPixels: CGFloat = 2048
    private static let quality: CGFloat = 0.8

    let id = UUID()
    let jpeg: Data
    let thumbnail: UIImage

    /// A photo from the bytes of any image the system can read.
    init(data: Data) throws {
        guard let image = UIImage(data: data) else {
            throw PhotoProblem(message: "That file isn't an image dadi can read.")
        }
        let longer = max(image.size.width, image.size.height) * image.scale
        let ratio = min(1, Self.maxPixels / max(longer, 1))
        let size = CGSize(width: image.size.width * image.scale * ratio, height: image.size.height * image.scale * ratio)
        guard let shrunk = image.preparingThumbnail(of: size),
              let encoded = shrunk.jpegData(compressionQuality: Self.quality),
              let thumbnail = shrunk.preparingThumbnail(of: CGSize(width: 240, height: 240 * size.height / size.width))
        else {
            throw PhotoProblem(message: "That image couldn't be prepared.")
        }
        jpeg = encoded
        self.thumbnail = thumbnail
    }

    /// The photo as Hath takes it on a message.
    var outbound: OutboundAttachment {
        OutboundAttachment(mediaType: "image/jpeg", data: jpeg.base64EncodedString(), filename: "photo-\(id.uuidString.prefix(8).lowercased()).jpg")
    }
}

/// A photo that could not be added.
struct PhotoProblem: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
