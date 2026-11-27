import Combine
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The message field and its send button, two shapes of one liquid glass:
/// once there is something to send, the button flows out of the field's end
/// on one spring and the field draws in to make room, and it flows back in
/// when the field empties. The glass only melds while the shapes move: at rest
/// the gap between them is wider than the container's merge distance, so no
/// bridge of glass is left between them. Sending puts the keyboard away, a beat after the bubble. Dadi's
/// composer is this; a thread's is written in the dock's accessory.
struct Composer: View {
    @Binding var text: String
    /// Photos and files waiting to go with the message.
    @Binding var files: [DraftFile]
    let placeholder: String
    /// A send is in flight: the button spins and another send waits.
    let busy: Bool
    /// True while the cursor is wanted in the field. Turning it off resigns the field, which lowers the keyboard and the
    /// composer riding it in one motion.
    var focusing = false
    let send: () -> Void

    @Namespace private var glass
    @FocusState private var focused: Bool
    @State private var attach = Attach.closed
    @State private var camera = CameraModel()
    @State private var batch = CaptureBatch<DraftFile>()
    @State private var libraryOpen = false
    @State private var filesOpen = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var problem: String?
    @State private var opened = 0
    @State private var dismissing = false
    /// The composer's width, which the open viewfinder fills.
    @State private var width: CGFloat = 0

    /// What the plus is showing: itself, with its menu of sources, or the camera.
    private enum Attach: Equatable {
        case closed, camera
    }

    /// The gap between field and button at rest, wider than `merge`.
    private let gap: CGFloat = 10
    /// How near the two shapes must be for their glass to meld.
    private let merge: CGFloat = 6

    private var ready: Bool { !busy && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty) }

    /// The button is out while there is something to send or a send is in flight.
    private var showsSend: Bool { ready || busy }

    var body: some View {
        VStack(spacing: 0) {
            if !files.isEmpty {
                FileStrip(files: $files)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomLeading)))
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
            fieldRow
        }
        .animation(Motion.settle, value: files)
        .animation(Motion.snap, value: problem)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: opened)
        .frame(maxWidth: 680)
        .photosPicker(isPresented: $libraryOpen, selection: $picked, maxSelectionCount: max(1, DraftFile.limit - files.count), matching: .images)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await addPicked(items) }
        }
        .fileImporter(isPresented: $filesOpen, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): addDocuments(urls)
            case .failure(let error): problem = error.localizedDescription
            }
        }
        .task { await camera.prepare() }
        .onDisappear { batch.release(into: &files) }
        .onChange(of: focusing, initial: true) { _, now in focused = now }
    }

    /// The plus, which is also the viewfinder: a glass circle at the field's
    /// start whose menu offers the sources. Choosing Camera grows it into
    /// the viewfinder while the field stays mounted, unseen and still holding
    /// the keyboard, and the send button gives way; it shrinks back into the
    /// plus when closed. The viewfinder is laid out at its open size from the
    /// start and the growing surface uncovers it from the plus's corner, so the
    /// live preview never resizes mid-animation.
    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
        return ZStack {
            switch attach {
            case .camera:
                CameraPanel(camera: camera, count: files.count, dismissing: dismissing, add: { files.append($0) }, batch: $batch, report: { problem = $0 }, close: closeCamera)
                    .frame(width: max(width, 46), height: CameraPanel.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.16)),
                        removal: .opacity.animation(.easeIn(duration: 0.2).delay(0.12))
                    ))
            case .closed:
                AttachMenu(choose: choose) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.sageDeep)
                        .frame(width: 46, height: 46)
                        .contentShape(.circle)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: attach == .closed ? 46 : .infinity)
        .frame(height: attach == .camera ? CameraPanel.height : 46)
        .background(Color.black.opacity(attach == .camera ? 1 : 0), in: shape)
        .clipShape(shape)
        .glassEffect(.regular.interactive(), in: shape)
        .glassEffectID("plus", in: glass)
    }

    private var fieldRow: some View {
        GlassEffectContainer(spacing: merge) {
            HStack(alignment: .bottom, spacing: attach == .closed ? gap : 0) {
                surface
                TextField(placeholder, text: $text, axis: .vertical)
                    .focused($focused)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .onSubmit(submit)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 23, style: .continuous))
                    .glassEffectID("field", in: glass)
                    .overlay {
                        RoundedRectangle(cornerRadius: 23, style: .continuous)
                            .strokeBorder(Color.sageLine.opacity(0.42), lineWidth: 1)
                    }
                    .frame(maxWidth: attach == .closed ? .infinity : 0)
                    .clipped()
                    .opacity(attach == .closed ? 1 : 0)
                    .allowsHitTesting(attach == .closed)
                    .accessibilityHidden(attach != .closed)
                if attach == .closed, showsSend {
                    Button(action: submit) {
                        ZStack {
                            if busy {
                                ProgressView().controlSize(.small).tint(.bone)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.bone)
                            }
                        }
                        .frame(width: 46, height: 46)
                        .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.sageDeep).interactive(), in: .circle)
                    .glassEffectID("send", in: glass)
                    .disabled(!ready)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Send")
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: attach)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: showsSend)
    }

    private func choose(_ source: ThreadAttach) {
        switch source {
        case .camera: openCamera()
        case .library: libraryOpen = true
        case .files: filesOpen = true
        }
    }

    /// Grows the plus into the viewfinder, leaving the keyboard where it is.
    private func openCamera() {
        problem = nil
        attach = .camera
        opened += 1
    }

    /// Adds the picked library photos, as many as the message has room for.
    private func addPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                files.append(try await DraftFile.picked(item))
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    /// Adds the files chosen in the document picker, as many as the message has room for.
    private func addDocuments(_ urls: [URL]) {
        for url in urls.prefix(max(0, DraftFile.limit - files.count)) {
            do {
                files.append(try DraftFile.document(at: url))
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    /// Closes in one motion: the controls fade while the surface shrinks back
    /// into the plus, the frozen preview clipped inside it; the panel stops the
    /// camera as it leaves.
    private func closeCamera() {
        batch.release(into: &files)
        guard attach == .camera, !dismissing else { return }
        dismissing = true
        attach = .closed
        Task {
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            dismissing = false
        }
    }

    /// How long the sent bubble leads before the keyboard starts down, so the
    /// two motions follow one another instead of landing together.
    private let keyboardLag: Duration = .milliseconds(160)

    /// Sends, then eases the keyboard down behind the bubble.
    private func submit() {
        closeCamera()
        guard ready else { return }
        send()
        Task {
            do { try await Task.sleep(for: keyboardLag) } catch { return }
            withAnimation(Motion.settle) { focused = false }
        }
    }
}

/// The photos and files waiting to be sent, as a row of tiles each with a button to take it back out: an image's own
/// thumbnail, any other file's icon and name. A tile shows its upload as it goes, and a failed one its reason below.
struct FileStrip: View {
    @Binding var files: [DraftFile]

    private var failures: [DraftFile] { files.filter(failed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(files) { file in
                        tile(file)
                            .overlay(alignment: .topTrailing) { remove(file) }
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, failures.isEmpty ? 12 : 2)
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
            ForEach(failures) { file in
                Label("\(file.name): \(message(file))", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
                    .padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ file: DraftFile) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack {
            if let thumbnail = file.thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFill()
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "doc").font(.system(size: 18)).foregroundStyle(.sageDeep)
                    Text(file.name).font(.caption2).foregroundStyle(.ink).lineLimit(2).truncationMode(.middle)
                }
                .padding(6)
                .background(.boneRaised)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(shape)
        .overlay { shape.strokeBorder(failed(file) ? Color.danger : .clear, lineWidth: 2) }
        .overlay { status(file) }
        .accessibilityLabel(file.name)
    }

    private func failed(_ file: DraftFile) -> Bool {
        if case .failed = file.upload { true } else { false }
    }

    private func message(_ file: DraftFile) -> String {
        if case .failed(let message) = file.upload { message } else { "" }
    }

    @ViewBuilder
    private func status(_ file: DraftFile) -> some View {
        switch file.upload {
        case .uploading:
            ProgressView().controlSize(.small).tint(.bone).padding(8).background(.ink.opacity(0.55), in: .circle)
        case .uploaded:
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.bone).padding(7).background(.sageDeep, in: .circle)
        case .pending, .failed:
            EmptyView()
        }
    }

    private func remove(_ file: DraftFile) -> some View {
        Button {
            file.discard()
            files.removeAll { $0.id == file.id }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.bone)
                .frame(width: 20, height: 20)
                .background(.ink.opacity(0.75), in: .circle)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .offset(x: 8, y: -8)
        .accessibilityLabel("Remove \(file.name)")
    }
}
