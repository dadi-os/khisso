import Foundation

/// The vault as the Chaavi page and its drawer share it: every item and
/// folder, the folder being browsed, the kind the list is narrowed to, and
/// the Face ID lock that guards every secret. Writes reload the vault, so
/// what shows is always Chaavi's.
@MainActor
@Observable
final class ChaaviStore {
    /// What the list is narrowed to.
    enum Kind: String, CaseIterable, Hashable {
        case all = "All items"
        case favorites = "Favorites"
        case logins = "Logins"
        case notes = "Secure notes"
        case other = "Cards and more"

        var symbol: String {
            switch self {
            case .all: "tray.full"
            case .favorites: "star"
            case .logins: "person.badge.key"
            case .notes: "note.text"
            case .other: "creditcard"
            }
        }

        /// Whether `item` is of this kind.
        func holds(_ item: ChaaviItem) -> Bool {
            switch self {
            case .all: true
            case .favorites: item.favorite
            case .logins: item.type == "login"
            case .notes: item.type == "note"
            case .other: item.type != "login" && item.type != "note"
            }
        }
    }

    let chaavi: ChaaviClient
    let vault = VaultLock()

    private(set) var items: [ChaaviItem] = []
    private(set) var folders: [ChaaviFolder] = []
    private(set) var loaded = false
    var error: String?
    /// The folder being browsed; nil at the top.
    var scope: String?
    var kind = Kind.all

    init(chaavi: ChaaviClient) {
        self.chaavi = chaavi
    }

    /// Reads every item and folder.
    func load() async {
        do {
            async let nextItems = chaavi.items()
            async let nextFolders = chaavi.folders()
            (items, folders) = try await (nextItems, nextFolders)
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    /// How many items are of `kind`.
    func count(_ kind: Kind) -> Int {
        items.filter(kind.holds).count
    }

    /// Saves a new item and reads the vault again.
    func create(_ item: ChaaviNewItem) async throws {
        _ = try await chaavi.create(item)
        await load()
    }

    /// Stars or unstars `item` and reads the vault again.
    func setFavorite(_ favorite: Bool, _ item: ChaaviItem) async throws {
        _ = try await chaavi.setFavorite(favorite, of: item.id)
        await load()
    }

    /// Deletes `item` and reads the vault again.
    func delete(_ item: ChaaviItem) async throws {
        try await chaavi.delete(item.id)
        await load()
    }
}
