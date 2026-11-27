import MarkdownView
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

extension EnvironmentValues {
    /// Nas, for a `box://` link to check that its file still exists. Set by `boxLinks(nas:)`.
    @Entry var boxNas: NasClient?
}

extension View {
    /// Makes the `box://` links below open in a `FileViewer` sheet, and lets each check that its file still exists.
    func boxLinks(nas: NasClient) -> some View {
        modifier(BoxLinks(nas: nas))
    }
}

private struct BoxLinks: ViewModifier {
    let nas: NasClient

    @State private var opened: BoxLink?

    func body(content: Content) -> some View {
        content
            .environment(\.boxNas, nas)
            .environment(\.openURL, OpenURLAction { url in
                guard let link = BoxLink(href: url.absoluteString) else { return .systemAction }
                opened = link
                return .handled
            })
            .sheet(item: $opened) { FileViewer(nas: nas, link: $0) }
    }
}

/// Whether a linked file is still on the box, asked of Nas once a minute per path.
@MainActor
enum BoxFiles {
    private static var checks: [String: (at: Date, gone: Bool)] = [:]
    private static let fresh: TimeInterval = 60

    /// Whether `error` from Nas's stat says the path no longer exists.
    nonisolated static func isGone(_ error: Error) -> Bool {
        (error as? ServiceError)?.status == 404
    }

    /// True only when Nas answers that `path` is gone. Any other failure leaves the link as it is: the file may still be
    /// there, and the viewer shows the failure when it is opened.
    static func gone(_ path: String, nas: NasClient) async -> Bool {
        if let check = checks[path], Date.now.timeIntervalSince(check.at) < fresh { return check.gone }
        do {
            _ = try await nas.stat(path)
            checks[path] = (.now, false)
            return false
        } catch where isGone(error) {
            checks[path] = (.now, true)
            return true
        } catch {
            return false
        }
    }
}

/// A `box://` link in a message: the file's icon before its name, in a capsule. A press opens it in the file viewer; holding
/// offers Open and Copy link. When Nas says the file is gone, the name is struck through and marked removed.
struct FileChip<Words: View>: View {
    let link: BoxLink
    @ViewBuilder let label: Words

    @Environment(\.openURL) private var openURL
    @Environment(\.boxNas) private var nas
    @State private var gone = false

    private var symbol: String {
        if link.folder { return "folder" }
        let type = UTType(filenameExtension: URL(filePath: link.path).pathExtension)
        if type?.conforms(to: .image) == true { return "photo" }
        return type?.conforms(to: .pdf) == true ? "doc.richtext" : "doc"
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.footnote).foregroundStyle(.sageDeep)
                label.strikethrough(gone).opacity(gone ? 0.7 : 1)
                if gone {
                    Text("File removed").font(.caption).foregroundStyle(.inkMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.boneRaised, in: .capsule)
            .overlay(Capsule().strokeBorder(.rule))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: open) { Label("Open", systemImage: "arrow.up.forward.app") }
            Button { UIPasteboard.general.string = link.href } label: { Label("Copy link", systemImage: "link") }
        }
        .task(id: link.path) {
            guard let nas else { return }
            gone = await BoxFiles.gone(link.path, nas: nas)
        }
        .accessibilityLabel(gone ? "\(link.name), removed" : link.name)
        .accessibilityHint(link.folder ? "Opens the folder" : "Opens the file")
    }

    private func open() {
        guard let url = URL(string: link.href) else { return }
        openURL(url)
    }
}

/// Draws a Markdown link to the box as a `FileChip`.
struct BoxLinkRenderer: MarkdownLinkRenderer {
    func makeBody(configuration: MarkdownLinkRendererConfiguration) -> some View {
        BoxLinkView(configuration: configuration)
    }
}

/// A box link's chip; a target that is not a box path is its text.
private struct BoxLinkView: View {
    let configuration: MarkdownLinkRendererConfiguration

    var body: some View {
        if let link = BoxLink(href: configuration.url.absoluteString) {
            FileChip(link: link) { configuration.label }
        } else {
            configuration.label
        }
    }
}

/// A file or folder on the box in a sheet: a file opens in QuickLook (PDF, images, text, office documents and more) with
/// Share for the file itself, a folder lists what is in it and opens each entry in turn. A removed file says so.
struct FileViewer: View {
    let nas: NasClient
    let link: BoxLink

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FileScreen(nas: nas, link: link)
                .navigationDestination(for: BoxLink.self) { FileScreen(nas: nas, link: $0) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                    }
                }
        }
    }
}

private struct FileScreen: View {
    let nas: NasClient
    let link: BoxLink

    private enum Content {
        case loading
        case gone
        case failed(String)
        case file(URL)
        case folder([NasFileEntry])
    }

    @State private var content = Content.loading

    var body: some View {
        Group {
            switch content {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .gone:
                ContentUnavailableView {
                    Label { Text(link.name).strikethrough() } icon: { Image(systemName: "questionmark.folder") }
                } description: {
                    Text("File removed")
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not open \(link.name)", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .file(let url):
                QuickLookPreview(url: url).ignoresSafeArea(edges: .bottom)
            case .folder(let entries):
                if entries.isEmpty {
                    ContentUnavailableView("Empty folder", systemImage: "folder")
                } else {
                    List(entries) { entry in row(entry) }
                }
            }
        }
        .background(.bone)
        .navigationTitle(link.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if case .file(let url) = content {
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: url) }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func row(_ entry: NasFileEntry) -> some View {
        let label = HStack {
            Image(systemName: entry.kind == .folder ? "folder" : "doc").foregroundStyle(.sageDeep)
            Text(entry.name).foregroundStyle(.ink).lineLimit(1)
            Spacer()
            if entry.kind == .file {
                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)).font(.caption).foregroundStyle(.inkMuted)
            }
        }
        if entry.kind == .symlink {
            label.opacity(0.5)
        } else {
            NavigationLink(value: BoxLink(path: entry.path, folder: entry.kind == .folder)) { label }
        }
    }

    private func load() async {
        content = .loading
        do {
            let entry = try await nas.stat(link.path)
            content = entry.kind == .folder ? .folder(try await nas.list(entry.path).entries) : .file(try await nas.download(entry))
        } catch is CancellationError {
            return
        } catch where BoxFiles.isGone(error) {
            content = .gone
        } catch {
            content = .failed(error.localizedDescription)
        }
    }
}

/// QuickLook's own preview of one file, filling its space.
private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Source { Source(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Source: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}
