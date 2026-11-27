import SwiftUI

/// The trail back from the browsed folder, "All items › Banking › Chase": the pieces of the path, with a long path
/// kept to its first segment and its last two and the middle gathered under one "…" menu.
enum Breadcrumb {
    /// One place on the path; tapping it browses `path` (nil is the top).
    struct Segment: Identifiable, Equatable {
        let title: String
        let path: String?
        var id: String { path ?? "" }
    }

    /// What the trail draws: a segment, or the segments the trail left out.
    enum Piece: Equatable, Identifiable {
        case segment(Segment)
        case hidden([Segment])

        var id: String {
            switch self {
            case .segment(let segment): segment.id
            case .hidden: "…"
            }
        }
    }

    /// The most segments drawn before the middle is gathered.
    static let capacity = 4

    /// Every place from the top to `scope`.
    static func segments(scope: String?, root: String) -> [Segment] {
        var path: [String] = []
        let folders = (scope?.split(separator: FolderTree.separator).map(String.init) ?? []).map { name -> Segment in
            path.append(name)
            return Segment(title: name, path: path.joined(separator: String(FolderTree.separator)))
        }
        return [Segment(title: root, path: nil)] + folders
    }

    /// The pieces to draw for `scope`; the last is where the person is.
    static func pieces(scope: String?, root: String) -> [Piece] {
        let all = segments(scope: scope, root: root)
        guard all.count > capacity else { return all.map(Piece.segment) }
        return [.segment(all[0]), .hidden(Array(all[1..<(all.count - 2)]))] + all.suffix(2).map(Piece.segment)
    }
}

/// The breadcrumb in the page's header type: ancestors quiet and tappable, the current folder in ink, chevrons
/// between, long names cut in the middle.
struct BreadcrumbBar: View {
    let scope: String?
    let root: String
    let browse: (String?) -> Void

    var body: some View {
        let pieces = Breadcrumb.pieces(scope: scope, root: root)
        HStack(spacing: 6) {
            ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.inkFaint)
                }
                let current = index == pieces.count - 1
                switch piece {
                case .segment(let segment):
                    Button { browse(segment.path) } label: { title(segment.title, current: current) }
                        .buttonStyle(.plain)
                        .disabled(current)
                case .hidden(let hidden):
                    Menu {
                        ForEach(hidden) { segment in Button(segment.title) { browse(segment.path) } }
                    } label: {
                        Text("…").font(.system(size: 15, weight: .semibold)).foregroundStyle(.inkMuted).frame(minWidth: 28, minHeight: 32)
                    }
                    .accessibilityLabel("Folders in between")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func title(_ text: String, current: Bool) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(current ? Color.ink : .inkMuted)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(minHeight: 32)
            .layoutPriority(current ? 1 : 0)
            .contentShape(.rect)
    }
}
