import Foundation
import Observation

/// Which services have changed, from their event streams, so pages read again
/// when there is something new instead of polling. Yaad (plans, memories and
/// the planner), Chaavi and Ghar announce every write; each count moves on
/// every announcement and on every (re)connect, since the streams do not
/// replay what happened while they were down. Nas's readings stay polled by
/// the System page, as on the desktop.
@MainActor
@Observable
final class LiveData {
    private(set) var yaad = 0
    private(set) var chaavi = 0
    private(set) var ghar = 0
    /// Why a stream last stopped; cleared once it connects again.
    private(set) var problem: String?

    /// The services that announce their changes.
    private enum Source: String {
        case yaad = "Yaad"
        case chaavi = "Chaavi"
        case ghar = "Ghar"
    }

    /// Follows every stream until cancelled.
    func follow(_ services: Services) async {
        async let yaad: Void = follow(.yaad, open: services.yaad.changes)
        async let chaavi: Void = follow(.chaavi, open: services.chaavi.changes)
        async let ghar: Void = follow(.ghar, open: services.ghar.changes)
        _ = await (yaad, chaavi, ghar)
    }

    /// Follows one stream, reopening a dropped one after a delay that doubles
    /// from one second up to thirty.
    private func follow(
        _ source: Source,
        open: @Sendable () async throws -> AsyncThrowingStream<Void, Error>
    ) async {
        var delay: Duration = .seconds(1)
        while !Task.isCancelled {
            do {
                let changes = try await open()
                problem = nil
                delay = .seconds(1)
                changed(source)
                for try await _ in changes { changed(source) }
            } catch is CancellationError {
                return
            } catch {
                problem = "\(source.rawValue) live updates stopped: \(error.localizedDescription)"
            }
            do { try await Task.sleep(for: delay) } catch { return }
            delay = min(delay * 2, .seconds(30))
        }
    }

    private func changed(_ source: Source) {
        switch source {
        case .yaad: yaad += 1
        case .chaavi: chaavi += 1
        case .ghar: ghar += 1
        }
    }
}
