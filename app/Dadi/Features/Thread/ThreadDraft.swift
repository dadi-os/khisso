import SwiftUI

/// How a photo is being added to a thread's message.
enum ThreadAttach: Equatable {
    case library, camera
}

/// What a thread's composer holds for one agent: the words, the photos, the message being quoted
/// and the send in flight. The composer in the thread's page writes into it and the thread reads it,
/// so the draft survives the thread being closed and opened again.
@MainActor
@Observable
final class ThreadDraft {
    var text = ""
    var photos: [DraftPhoto] = []
    /// The message being replied to, quoted ahead of the reply.
    var quote: DurableMessage?
    var sendError: String?
    /// True while the message is with Hath.
    private(set) var sending = false
    /// The message Hath last accepted, for the thread to show.
    private(set) var delivered: DurableMessage?
    /// Counts accepted sends, for the thread's haptic.
    private(set) var sent = 0
    /// The photo source being opened, which the thread presents.
    var attaching: ThreadAttach?
    /// Why the last photo was not added.
    var photoProblem: String?

    /// Whether there is something to send and nothing already going.
    var canSend: Bool { Self.canSend(text: text, photos: photos.count, sending: sending) }

    /// Whether `text` or `photos` give a message to send while nothing is `sending`.
    nonisolated static func canSend(text: String, photos: Int, sending: Bool) -> Bool {
        !sending && (photos > 0 || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Quotes `message` ahead of the reply.
    func reply(to message: DurableMessage) {
        quote = message
    }

    /// Sends the draft to `agentId`. A failure keeps the draft and sets `sendError`.
    func send(_ hath: HathClient, to agentId: String) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attached = photos
        guard canSend else { return }
        let content = quote.map { QuoteCard.blockquote(plainText($0.content)) + words } ?? words
        sending = true
        sendError = nil
        Task {
            defer { sending = false }
            do {
                let reply = try await hath.send(content, to: agentId, attachments: attached.map(\.outbound))
                text = ""
                photos = []
                quote = nil
                sent += 1
                delivered = DurableMessage(seq: reply.seq, fromAgentId: nil, toAgentId: agentId, content: reply.content, attachments: reply.attachments, kind: .message, status: nil, createdAt: reply.createdAt)
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
