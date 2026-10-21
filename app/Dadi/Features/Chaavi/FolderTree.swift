import Foundation

/// Chaavi's folders as a tree, matching thaali's `chaavi/folders.ts`: the vault
/// stores folders flat and a slash in a name nests it. A parent can exist only
/// as the start of its children's names, with no folder of its own.
enum FolderTree {
    static let separator: Character = "/"

    /// A folder directly under a scope, with the items in it and below it.
    struct Child: Hashable, Identifiable {
        /// Full path, e.g. "Development/fliks-gg".
        let path: String
        /// The last path segment.
        let name: String
        let count: Int

        var id: String { path }
    }

    /// True when `path` is `scope` or sits anywhere under it.
    static func isWithin(_ path: String, _ scope: String) -> Bool {
        path == scope || path.hasPrefix(scope + String(separator))
    }

    /// The folders one level under `scope` (nil for the top), in name order,
    /// each counting the items anywhere in its subtree.
    static func children(of scope: String?, folders: [ChaaviFolder], items: [ChaaviItem]) -> [Child] {
        let prefix = scope.map { $0 + String(separator) } ?? ""
        let names = Set(folders.compactMap { folder -> String? in
            guard folder.name.hasPrefix(prefix), folder.name.count > prefix.count else { return nil }
            return folder.name.dropFirst(prefix.count).split(separator: separator).first.map(String.init)
        })
        let paths = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.name) })
        return names.sorted { $0.localizedCompare($1) == .orderedAscending }.map { name in
            let path = prefix + name
            let count = items.filter { item in item.folderId.flatMap { paths[$0] }.map { isWithin($0, path) } ?? false }.count
            return Child(path: path, name: name, count: count)
        }
    }

    /// The items in `scope` and every folder under it; every item at the top.
    static func items(in scope: String?, folders: [ChaaviFolder], items: [ChaaviItem]) -> [ChaaviItem] {
        guard let scope else { return items }
        let paths = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.name) })
        return items.filter { item in item.folderId.flatMap { paths[$0] }.map { isWithin($0, scope) } ?? false }
    }
}
