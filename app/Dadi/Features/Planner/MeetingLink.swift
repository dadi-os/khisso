import Foundation

/// A video-call link a plan carries, with the service it is for.
struct MeetingLink: Equatable {
    let url: URL
    /// "Google Meet", "Zoom", "Microsoft Teams", or "Video call" for any other service.
    let service: String

    /// The link's host, as the Join row shows it.
    var host: String { url.host() ?? url.absoluteString }
}

/// Finds the video-call link of a plan: in its place's address or title, its body or its notes.
enum Meeting {
    private static let services: [(hosts: [String], name: String)] = [
        (["meet.google.com"], "Google Meet"),
        (["zoom.us", "zoom.com"], "Zoom"),
        (["teams.microsoft.com", "teams.live.com"], "Microsoft Teams"),
        (["webex.com", "whereby.com", "facetime.apple.com", "bluejeans.com", "gotomeeting.com", "meet.jit.si", "around.co"], "Video call"),
    ]

    /// The first link in `text` that belongs to a known video-call service; nil when none does.
    static func link(in text: String) -> MeetingLink? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url, let scheme = url.scheme, ["http", "https"].contains(scheme), let host = url.host()?.lowercased() else { continue }
            if let service = services.first(where: { $0.hosts.contains { host == $0 || host.hasSuffix("." + $0) } }) {
                return MeetingLink(url: url, service: service.name)
            }
        }
        return nil
    }

    /// True when `text` is only the link itself, so a place made of it is not a real address.
    static func isLink(_ text: String?) -> Bool {
        guard let text else { return false }
        return link(in: text) != nil
    }
}

/// The video-call link of `plan`: its place's address or title, then its body, then its notes; nil for a plan that is
/// not virtual.
func meetingLink(_ plan: Plan) -> MeetingLink? {
    let texts = [plan.place?.address, plan.place?.title, plan.body] + plan.notes.flatMap { [$0.title, $0.body] }
    return texts.compactMap { $0 }.lazy.compactMap { Meeting.link(in: $0) }.first
}

extension Plan {
    /// The place's real address: nil when it has none or when the "address" is the call link.
    var street: String? {
        guard let address = place?.address, !Meeting.isLink(address) else { return nil }
        return address
    }
}
