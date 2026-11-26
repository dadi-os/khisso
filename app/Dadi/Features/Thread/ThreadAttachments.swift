import PhotosUI
import SwiftUI

extension View {
    /// Presents the photo library and the add-photo failure for `draft`, from the thread itself. The
    /// camera sits in the thread's page above the composer, so the keyboard stays up while it is open;
    /// `camera` is prepared ahead.
    func threadAttachments(_ draft: ThreadDraft, camera: CameraModel) -> some View {
        modifier(ThreadAttachments(draft: draft, camera: camera))
    }
}

private struct ThreadAttachments: ViewModifier {
    let draft: ThreadDraft
    let camera: CameraModel

    @State private var picked: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: present(.library), selection: $picked, maxSelectionCount: max(1, DraftPhoto.limit - draft.photos.count), matching: .images)
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                picked = []
                Task { await add(items) }
            }
            .task { await camera.prepare() }
            .alert("Photo not added", isPresented: Binding { draft.photoProblem != nil } set: { if !$0 { draft.photoProblem = nil } }) {
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
                draft.photos.append(try await DraftPhoto.picked(item))
            } catch {
                draft.photoProblem = error.localizedDescription
            }
        }
    }
}
