import Foundation

/// Thrown after every staged file was tried when some failed; each failed file already holds its own error.
struct UploadFailed: LocalizedError, Equatable {
    let failed: Int

    var errorDescription: String? { failed == 1 ? "1 file did not upload" : "\(failed) files did not upload" }
}

/// How a message carries files: they upload to the month's Inbox on the box, and the message holds one `box://` link
/// per file ahead of what was typed.
enum Inbox {
    /// Uploads every file not yet on the box to this month's Inbox, one after another, reporting each file's state as it
    /// changes. A file an earlier attempt already uploaded is not sent again. Every file is tried.
    /// - Parameter put: puts a file in a folder on the box and answers where it landed (`NasClient.upload`).
    /// - Returns: the files' paths on the box, in order.
    /// - Throws: `UploadFailed` when any upload failed.
    @MainActor
    static func upload(_ files: [DraftFile], now: Date, put: (String, DraftFile) async throws -> NasUploaded, report: (UUID, UploadState) -> Void) async throws -> [String] {
        let folder = BoxLink.inboxFolder(now)
        var paths: [String] = []
        var failed = 0
        for file in files {
            if case .uploaded(let path) = file.upload {
                paths.append(path)
                continue
            }
            report(file.id, .uploading)
            do {
                let uploaded = try await put(folder, file)
                report(file.id, .uploaded(path: uploaded.path))
                paths.append(uploaded.path)
            } catch {
                report(file.id, .failed(error.localizedDescription))
                failed += 1
            }
        }
        guard failed == 0 else { throw UploadFailed(failed: failed) }
        return paths
    }

    /// A message's text: a link per uploaded file on its own line, then what was typed (just the links when nothing was).
    static func message(paths: [String], typed: String) -> String {
        let links = paths.map { BoxLink(path: $0, folder: false).markdown }
        return (links + [typed.trimmingCharacters(in: .whitespacesAndNewlines)]).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
