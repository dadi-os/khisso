import PhotosUI
import SwiftUI

extension View {
    /// Presents the photo library, the camera and the add-photo failure for `draft`, from the thread
    /// itself so they outlive the composer moving between the dock and the keyboard.
    func threadAttachments(_ draft: ThreadDraft) -> some View {
        modifier(ThreadAttachments(draft: draft))
    }
}

private struct ThreadAttachments: ViewModifier {
    let draft: ThreadDraft

    @State private var camera = CameraModel()
    @State private var picked: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: present(.library), selection: $picked, maxSelectionCount: max(1, DraftPhoto.limit - draft.photos.count), matching: .images)
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                picked = []
                Task { await add(items) }
            }
            .fullScreenCover(isPresented: present(.camera)) {
                CameraPanel(camera: camera, count: draft.photos.count, dismissing: false, add: { draft.photos.append($0) }, close: closeCamera)
                    .background(.black)
                    .ignoresSafeArea()
                    .task { await camera.start() }
            }
            .onChange(of: draft.attaching) { _, source in
                if source == .camera { Task { await camera.warm() } }
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

    private func closeCamera() {
        draft.attaching = nil
        camera.release()
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
