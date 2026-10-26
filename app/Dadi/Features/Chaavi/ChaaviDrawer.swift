import SwiftUI

/// Chaavi's drawer: the vault by kind with counts (all, favorites, logins,
/// notes, the rest), the top folders, and the lock: whether Face ID is
/// holding open now, with Lock now to make the next secret ask again.
struct ChaaviDrawer: View {
    let store: ChaaviStore
    /// Narrows the page to a kind, or opens a folder, and closes the drawer.
    let choose: (ChaaviStore.Kind, String?) -> Void

    @State private var locked = 0

    var body: some View {
        let folders = FolderTree.children(of: nil, folders: store.folders, items: store.items)
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                heading("KINDS")
                ForEach(ChaaviStore.Kind.allCases, id: \.self) { kind in
                    let count = store.count(kind)
                    if kind == .all || count > 0 {
                        row(kind.rawValue, symbol: kind.symbol, count: count, current: store.kind == kind && (kind != .all || store.scope == nil)) {
                            choose(kind, nil)
                        }
                    }
                }
            }
            if !folders.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    heading("FOLDERS")
                    ForEach(folders) { folder in
                        row(folder.name, symbol: "folder", count: folder.count, current: store.kind == .all && store.scope.map { FolderTree.isWithin($0, folder.path) } == true) {
                            choose(.all, folder.path)
                        }
                    }
                }
            }
            Button {
                store.vault.lock()
                locked += 1
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: store.vault.isOpen ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.sageDeep)
                        .frame(width: 32, height: 32)
                        .background(.sage.opacity(0.2), in: .circle)
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.vault.isOpen ? "Lock now" : "Locked").font(.body.weight(.semibold)).foregroundStyle(.ink)
                        Text(store.vault.isOpen ? "Face ID is holding Chaavi open" : "Face ID asks before any secret")
                            .font(.footnote)
                            .foregroundStyle(.inkMuted)
                    }
                    Spacer()
                }
                .padding(10)
                .background(.sage.opacity(0.14), in: .rect(cornerRadius: 16, style: .continuous))
                .contentShape(.rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(!store.vault.isOpen)
        }
        .padding(.horizontal, 14)
        .animation(Motion.snap, value: store.vault.isOpen)
        .sensoryFeedback(.impact(weight: .medium), trigger: locked)
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(1.4)
            .foregroundStyle(.inkFaint)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
    }

    private func row(_ title: String, symbol: String, count: Int, current: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.sageDeep)
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                Spacer()
                Text("\(count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.inkMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(current ? Color.sage.opacity(0.16) : .clear, in: .rect(cornerRadius: 14, style: .continuous))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .animation(Motion.snap, value: current)
    }
}
