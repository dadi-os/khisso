import SwiftUI

/// Where a file for a thread's message comes from.
enum ThreadAttach: Equatable {
    case library, camera, files
}

/// What a thread's composer holds for one agent: the words, the staged files, the message being quoted
/// and the send in flight. The composer in the thread's page writes into it and the thread reads it,
/// so the draft survives the thread being closed and opened again.
@MainActor
@Observable
final class ThreadDraft {
    var text = ""
    var files: [DraftFile] = []
    /// The message being replied to, quoted ahead of the reply.
    var quote: DurableMessage?
    var sendError: String?
    /// True while the message is with Hath.
    private(set) var sending = false
    /// The message Hath last accepted, for the thread to show.
    private(set) var delivered: DurableMessage?
    /// Counts accepted sends, for the thread's haptic.
    private(set) var sent = 0
    /// The file source being opened, which the thread presents. Whatever closes the viewfinder, the pictures it
    /// already took in several-photo mode join `files`.
    var attaching: ThreadAttach? {
        didSet {
            if attaching != .camera { shots.release(into: &files) }
        }
    }
    /// Pictures the open viewfinder has taken and not yet attached.
    var shots = CaptureBatch<DraftFile>()
    /// Why the last photo or file was not added.
    var photoProblem: String?

    /// Whether there is something to send and nothing already going.
    var canSend: Bool { Self.canSend(text: text, files: files.count, sending: sending) }

    /// Whether `text` or `files` give a message to send while nothing is `sending`.
    nonisolated static func canSend(text: String, files: Int, sending: Bool) -> Bool {
        !sending && (files > 0 || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Quotes `message` ahead of the reply.
    func reply(to message: DurableMessage) {
        quote = message
    }

    /// Uploads the staged files to the month's Inbox through `nas`, then sends `agentId` one link per file and the words.
    /// A failure keeps the words and every file, each with its own state, and sets `sendError`; sending again skips the
    /// files already on the box.
    func send(_ hath: HathClient, nas: NasClient, to agentId: String) {
        shots.release(into: &files)
        guard canSend else { return }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let typed = quote.map { QuoteCard.blockquote(plainText($0.content)) + words } ?? words
        sending = true
        sendError = nil
        Task {
            defer { sending = false }
            do {
                let paths = try await Inbox.upload(files, now: .now, put: { folder, file in try await nas.upload(file.url, named: file.name, mediaType: file.mediaType, to: folder) }, report: { files.setUpload($0, $1) })
                let reply = try await hath.send(Inbox.message(paths: paths, typed: typed), to: agentId)
                files.forEach { $0.discard() }
                text = ""
                files = []
                quote = nil
                sent += 1
                delivered = DurableMessage(seq: reply.seq, fromAgentId: nil, toAgentId: agentId, content: reply.content, kind: .message, status: nil, createdAt: reply.createdAt)
            } catch {
                sendError = error.localizedDescription
            }
        }
    }
}

/// The drafts of every thread, one per agent, kept while the person moves between pages.
@MainActor
final class ThreadDrafts {
    private var drafts: [String: ThreadDraft] = [:]

    /// `agentId`'s draft, made on first use.
    func draft(for agentId: String) -> ThreadDraft {
        if let existing = drafts[agentId] { return existing }
        let made = ThreadDraft()
        drafts[agentId] = made
        return made
    }
}
