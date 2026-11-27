import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Presents the photo library, the document picker and the add failure for `draft`, from the thread itself. The
    /// camera sits in the thread's page above the composer, so the keyboard stays up while it is open;
    /// `camera` is prepared ahead.
    func threadFilePickers(_ draft: ThreadDraft, camera: CameraModel) -> some View {
        modifier(ThreadFilePickers(draft: draft, camera: camera))
    }
}

private struct ThreadFilePickers: ViewModifier {
    let draft: ThreadDraft
    let camera: CameraModel

    @State private var picked: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: present(.library), selection: $picked, maxSelectionCount: max(1, DraftFile.limit - draft.files.count), matching: .images)
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                picked = []
                Task { await add(items) }
            }
            .fileImporter(isPresented: present(.files), allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): addDocuments(urls)
                case .failure(let error): draft.photoProblem = error.localizedDescription
                }
            }
            .task { await camera.prepare() }
            .alert("Not added", isPresented: Binding { draft.photoProblem != nil } set: { if !$0 { draft.photoProblem = nil } }) {
                Button("OK") {}
            } message: {
                Text(draft.photoProblem ?? "")
            }
    }

    private func present(_ source: ThreadAttach) -> Binding<Bool> {
        Binding { draft.attaching == source } set: { if !$0, draft.attaching == source { draft.attaching = nil } }
    }

    /// Adds the picked library photos, as many as the message has room for.
    private func add(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                draft.files.append(try await DraftFile.picked(item))
            } catch {
                draft.photoProblem = error.localizedDescription
            }
        }
    }

    /// Adds the files chosen in the document picker, as many as the message has room for.
    private func addDocuments(_ urls: [URL]) {
        for url in urls.prefix(max(0, DraftFile.limit - draft.files.count)) {
            do {
                draft.files.append(try DraftFile.document(at: url))
            } catch {
                draft.photoProblem = error.localizedDescription
            }
        }
    }
}
