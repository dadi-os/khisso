import LocalAuthentication
import SwiftUI
import UIKit

/// Chaavi: the vault's logins and notes, browsed by folder or searched across
/// the whole vault, favorites first. Nothing
/// secret is fetched until it is asked for: copying or revealing a password
/// or code asks for Face ID or Touch ID, which then holds for five minutes.
/// Copies stay on this device and clear after 90 seconds.
struct ChaaviPage: View {
    let chaavi: ChaaviClient

    @State private var items: [ChaaviItem] = []
    @State private var folders: [ChaaviFolder] = []
    /// The folder being browsed; nil at the top.
    @State private var scope: String?
    @State private var query = ""
    @State private var loaded = false
    @State private var error: String?
    @State private var opened: ChaaviItem?
    @State private var vault = VaultLock()
    @State private var copied: String?
    @State private var copies = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.danger)
                }
                if loaded && shown.isEmpty && error == nil {
                    ContentUnavailableView(query.isEmpty ? "The vault is empty" : "No matches", systemImage: "key", description: Text(query.isEmpty ? "Logins saved in Chaavi show up here." : "Nothing in Chaavi matches \u{201C}\(query)\u{201D}."))
                        .foregroundStyle(.inkMuted)
                        .padding(.top, 40)
                }
                if query.isEmpty {
                    if let scope {
                        breadcrumb(scope)
                    }
                    ForEach(FolderTree.children(of: scope, folders: folders, items: items)) { folder in
                        Button { withAnimation(Motion.settle) { self.scope = folder.path } } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.sageDeep)
                                    .frame(width: 42, height: 42)
                                    .background(.sage.opacity(0.14), in: .rect(cornerRadius: 12, style: .continuous))
                                Text(folder.name).font(.body.weight(.semibold)).foregroundStyle(.ink)
                                Spacer()
                                Text("\(folder.count)").font(.footnote.monospacedDigit()).foregroundStyle(.inkFaint)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.inkFaint)
                            }
                            .padding(12)
                            .background(.boneRaised.opacity(0.7), in: .rect(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                ForEach(shown) { item in
                    Button { opened = item } label: {
                        ItemRow(item: item, copy: { copyPassword(item) })
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .animation(Motion.settle, value: shown)
        }
        .safeAreaBar(edge: .top) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.inkFaint)
                TextField("Search Chaavi", text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.inkFaint) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .overlay(alignment: .bottom) {
            if let copied {
                Label(copied, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.snap, value: copied)
        .sensoryFeedback(.success, trigger: copies)
        .refreshable { await load() }
        .sheet(item: $opened) { item in
            ItemDetail(item: item, chaavi: chaavi, vault: vault, copy: copy)
                .fittedSheet()
                .presentationBackground(.thinMaterial)
        }
        .navigationTitle("Chaavi")
        .task { await load() }
    }

    /// Items matching the search across the vault, or the browsed folder's
    /// items, favorites first, then by name.
    private var shown: [ChaaviItem] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return (needle.isEmpty ? FolderTree.items(in: scope, folders: folders, items: items) : items)
            .filter { item in
                needle.isEmpty || item.name.lowercased().contains(needle)
                    || (item.login?.username?.lowercased().contains(needle) ?? false)
                    || (item.host?.lowercased().contains(needle) ?? false)
            }
            .sorted { ($0.favorite ? 0 : 1, $0.name.lowercased()) < ($1.favorite ? 0 : 1, $1.name.lowercased()) }
    }

    /// The trail back from the browsed folder: the top, then each parent.
    private func breadcrumb(_ scope: String) -> some View {
        let parts = scope.split(separator: FolderTree.separator).map(String.init)
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                Button("Chaavi") { withAnimation(Motion.settle) { self.scope = nil } }
                ForEach(parts.indices, id: \.self) { index in
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.inkFaint)
                    let path = parts[0...index].joined(separator: String(FolderTree.separator))
                    Button(parts[index]) { withAnimation(Motion.settle) { self.scope = path } }
                        .disabled(index == parts.count - 1)
                }
            }
            .font(.subheadline.weight(.semibold))
            .tint(.sageDeep)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func load() async {
        do {
            async let nextItems = chaavi.items()
            async let nextFolders = chaavi.folders()
            (items, folders) = try await (nextItems, nextFolders)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    private func copyPassword(_ item: ChaaviItem) {
        Task {
            do {
                try await vault.unlock()
                copy(try await chaavi.reveal("password", of: item.id), "Password copied")
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Puts `value` on this device's clipboard for 90 seconds and says so.
    private func copy(_ value: String, _ note: String) {
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: value]], options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(90)])
        copies += 1
        copied = note
        Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if copied == note { copied = nil }
        }
    }
}

/// Asks for Face ID or Touch ID before a secret leaves Chaavi; a success holds
/// for five minutes.
@MainActor
@Observable
final class VaultLock {
    private var until: Date?

    /// Why the vault would not open.
    struct Refused: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func unlock() async throws {
        if let until, until > .now { return }
        let context = LAContext()
        var problem: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problem) else {
            throw Refused(message: problem?.localizedDescription ?? "This device can't confirm it's you.")
        }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Chaavi to see or copy secrets")
        } catch {
            throw Refused(message: error.localizedDescription)
        }
        until = .now.addingTimeInterval(300)
    }
}

/// One vault item in the list: its site's initial, name, username, and a copy
/// button for logins with a password.
private struct ItemRow: View {
    let item: ChaaviItem
    let copy: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(String((item.host ?? item.name).prefix(1)).uppercased())
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(SiteHue.of(item.host ?? item.name))
                .frame(width: 42, height: 42)
                .background(SiteHue.of(item.host ?? item.name).opacity(0.14), in: .rect(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if item.favorite {
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.clay).offset(x: 4, y: -4)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.semibold)).foregroundStyle(.ink).lineLimit(1)
                Text(item.login?.username ?? kind)
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if item.login?.hasPassword == true {
                Button(action: copy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Copy password for \(item.name)")
            }
        }
        .padding(12)
        .background(.boneRaised.opacity(0.7), in: .rect(cornerRadius: 18, style: .continuous))
        .contentShape(.rect)
    }

    private var kind: String {
        switch item.type {
        case "note": "Secure note"
        case "card": "Card"
        case "identity": "Identity"
        case "sshKey": "SSH key"
        default: "Item"
        }
    }
}

/// An item's detail: its username, a password that stays masked until it is
/// revealed, the current one-time code with its countdown, and its website.
private struct ItemDetail: View {
    let item: ChaaviItem
    let chaavi: ChaaviClient
    let vault: VaultLock
    let copy: (String, String) -> Void

    @State private var password: String?
    @State private var totp: ChaaviTotp?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Text(String((item.host ?? item.name).prefix(1)).uppercased())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(SiteHue.of(item.host ?? item.name))
                    .frame(width: 56, height: 56)
                    .background(SiteHue.of(item.host ?? item.name).opacity(0.14), in: .rect(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.title3.weight(.semibold)).foregroundStyle(.ink)
                    if let host = item.host { Text(host).font(.footnote).foregroundStyle(.inkMuted) }
                }
            }
            if let login = item.login {
                if let username = login.username {
                    field("Username", value: username, secret: false) { copy(username, "Username copied") }
                }
                if login.hasPassword {
                    field("Password", value: password ?? "••••••••••••", secret: password == nil) {
                        run {
                            let value = try await chaavi.reveal("password", of: item.id)
                            copy(value, "Password copied")
                        }
                    } reveal: {
                        if password == nil {
                            run { password = try await chaavi.reveal("password", of: item.id) }
                        } else {
                            password = nil
                        }
                    }
                }
                if login.hasTotp {
                    totpRow
                }
                if let host = item.host, let url = URL(string: "https://\(host)") {
                    Link(destination: url) {
                        Label("Open \(host)", systemImage: "safari")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.danger)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private func field(_ title: String, value: String, secret: Bool, copy: @escaping () -> Void, reveal: (() -> Void)? = nil) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.inkFaint)
                Text(value)
                    .font(.body.monospaced())
                    .foregroundStyle(.ink)
                    .blur(radius: secret ? 3 : 0)
                    .animation(Motion.settle, value: secret)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
            Spacer()
            if let reveal {
                Button(action: reveal) { Image(systemName: secret ? "eye" : "eye.slash") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(secret ? "Show \(title)" : "Hide \(title)")
            }
            Button(action: copy) { Image(systemName: "doc.on.doc") }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Copy \(title)")
        }
        .padding(14)
        .background(.boneRaised.opacity(0.7), in: .rect(cornerRadius: 16, style: .continuous))
    }

    private var totpRow: some View {
        HStack(spacing: 14) {
            if let totp {
                ZStack {
                    Circle().stroke(.sage.opacity(0.18), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(totp.remaining) / CGFloat(totp.period))
                        .stroke(.sageDeep, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(totp.remaining)").font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(.sageDeep)
                }
                .frame(width: 34, height: 34)
                Text(totp.code.chunked)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.ink)
                    .contentTransition(.numericText())
                Spacer()
                Button { copy(totp.code, "Code copied") } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            } else {
                Text("One-time code").font(.body.weight(.medium)).foregroundStyle(.ink)
                Spacer()
                Button("Show") { run { totp = try await chaavi.totp(of: item.id) } }
                    .buttonStyle(.glass)
            }
        }
        .padding(14)
        .background(.boneRaised.opacity(0.7), in: .rect(cornerRadius: 16, style: .continuous))
        .task(id: totp?.code) {
            guard let current = totp else { return }
            do {
                try await Task.sleep(for: .seconds(current.remaining))
                totp = try await chaavi.totp(of: item.id)
            } catch is CancellationError {
                return
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    /// Unlocks the vault, then runs `work`, showing why if either fails.
    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await vault.unlock()
                try await work()
                problem = nil
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}

private extension String {
    /// "123456" as "123 456".
    var chunked: String {
        count == 6 ? "\(prefix(3)) \(suffix(3))" : self
    }
}

/// A site's color for its letter tile, the same every time: sage, clay or tide.
private enum SiteHue {
    static func of(_ site: String) -> Color {
        let palette: [Color] = [.sageDeep, .clay, .tide]
        let sum = site.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }
}
