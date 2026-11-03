import SwiftUI

/// The full-height sheet Ankur acts in: a task's browser or terminal with its helper still working
/// until his first touch. The first input pauses the helper (Nas does it), the banner says so, and
/// closing a paused task asks what happens to it: resume the loop, hand it back with a note, or
/// stop it. Closing a sheet nothing was done in just closes.
struct TaskSheet: View {
    let nas: NasClient
    let task: NasTask
    /// The owning agent's name.
    let owner: String
    /// Reads the tasks again after the input paused the helper or the hand back changed it.
    let changed: () async -> Void

    @Environment(\.dismiss) private var dismiss
    /// True once Ankur has sent input from this sheet, before the task list says paused.
    @State private var driven = false
    @State private var closing = false
    @State private var noting = false
    @State private var note = ""
    @State private var problem: String?
    @State private var busy = false

    private var paused: Bool { driven || task.status == "paused" }

    var body: some View {
        VStack(spacing: 10) {
            header
            if paused { banner }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.danger).padding(.horizontal, 16)
            }
            if task.kind == "browser", let resource = task.resource, let browserId = Int(resource) {
                BrowserDrive(nas: nas, browserId: browserId, paused: paused, send: input)
            } else if let resource = task.resource {
                TerminalDrive(nas: nas, terminalId: resource, paused: paused, send: input)
            } else {
                Text(task.state).font(.footnote).foregroundStyle(.inkMuted).padding()
                Spacer()
            }
        }
        .padding(.top, 8)
        .interactiveDismissDisabled(paused)
        .confirmationDialog("\(task.route) is paused", isPresented: $closing, titleVisibility: .visible) {
            Button("Resume the loop") { finish { _ = try await nas.resume(task, note: nil) } }
            Button("Hand back with a note") { noting = true }
            Button("Stop the task", role: .destructive) { finish { _ = try await nas.stop(task) } }
            Button("Keep driving", role: .cancel) {}
        } message: {
            Text(task.purpose)
        }
        .alert("Hand it back", isPresented: $noting) {
            TextField("What you did", text: $note, axis: .vertical)
            Button("Hand back") { finish { _ = try await nas.resume(task, note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(owner) is told where you left it and carries on.")
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 0) {
                Text(task.route).font(.subheadline.monospaced().weight(.semibold)).foregroundStyle(.ink).lineLimit(1)
                Text(owner).font(.caption).foregroundStyle(.inkMuted).lineLimit(1)
            }
            .padding(.horizontal, 90)
            HStack {
                Spacer()
                Button("Close") { paused ? (closing = true) : dismiss() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.sageDeep)
                    .frame(minWidth: 70, minHeight: 44, alignment: .trailing)
                    .disabled(busy)
            }
            .padding(.horizontal, 16)
        }
    }

    private var banner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pause.fill").font(.footnote).foregroundStyle(.tideText).padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Paused while you drive").font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                Text("\(owner)'s helper waits. Closing asks what happens next.")
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.tide.opacity(0.2), in: .rect(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    /// Sends Ankur's input; the first one pauses the helper, so the tasks are read again after it.
    private func input(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                problem = nil
                if !driven { driven = true }
                await changed()
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    /// Runs the hand back or the stop, then closes the sheet.
    private func finish(_ action: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await action()
                await changed()
                dismiss()
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// A browser filling its sheet: taps go in at the point touched, the keyboard types into the focused
/// field, and back and reload step through its history.
private struct BrowserDrive: View {
    let nas: NasClient
    let browserId: Int
    let paused: Bool
    let send: (@escaping () async throws -> Void) -> Void

    /// Zero-width spaces under the hidden field, so a delete always changes it.
    private static let seed = String(repeating: "\u{200B}", count: 256)

    @State private var typed = BrowserDrive.seed
    @FocusState private var keyboard: Bool

    var body: some View {
        VStack(spacing: 10) {
            BrowserView(nas: nas, browserId: browserId)
                .overlay {
                    GeometryReader { geometry in
                        Color.clear
                            .contentShape(.rect)
                            .gesture(
                                DragGesture(minimumDistance: 0).onEnded { drag in
                                    let x = min(max(drag.location.x / geometry.size.width, 0), 1)
                                    let y = min(max(drag.location.y / geometry.size.height, 0), 1)
                                    send { try await nas.browserInput(browserId, events: [.pointer("move", x: x, y: y), .pointer("down", x: x, y: y), .pointer("up", x: x, y: y)]) }
                                }
                            )
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(paused ? Color.sageDeep : .clear, lineWidth: 2) }
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
            TextField("", text: $typed)
                .focused($keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .onChange(of: typed) { old, new in type(from: old, to: new) }
                .onSubmit { send { try await nas.browserInput(browserId, events: BrowserInputEvent.press(key: "Enter", code: "Enter", keyCode: 13, text: "\r")) } }
            HStack {
                tool("chevron.left", "Back") { send { try await nas.browserNavigate(browserId, action: "back") } }
                tool("arrow.clockwise", "Reload") { send { try await nas.browserNavigate(browserId, action: "reload") } }
                tool("keyboard", keyboard ? "Hide keyboard" : "Show keyboard") { keyboard.toggle() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func tool(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.ink)
        .accessibilityLabel(label)
    }

    /// Sends what the keyboard added to or took from the hidden field as key presses.
    private func type(from old: String, to new: String) {
        var events: [BrowserInputEvent] = []
        if new.count > old.count {
            for character in new.dropFirst(old.count) {
                let text = String(character)
                events += BrowserInputEvent.press(key: text, code: "", keyCode: Int(text.uppercased().unicodeScalars.first?.value ?? 0), text: text)
            }
        } else {
            for _ in 0..<(old.count - new.count) { events += BrowserInputEvent.press(key: "Backspace", code: "Backspace", keyCode: 8) }
        }
        guard !events.isEmpty else { return }
        send { try await nas.browserInput(browserId, events: events) }
    }
}

/// A terminal filling its sheet: its pane, a key row and a command line that types its text and Enter.
private struct TerminalDrive: View {
    let nas: NasClient
    let terminalId: String
    let paused: Bool
    let send: (@escaping () async throws -> Void) -> Void

    private static let keys: [(label: String, name: String)] = [("esc", "Escape"), ("tab", "Tab"), ("\u{2191}", "Up"), ("\u{2193}", "Down"), ("Ctrl-C", "C-c")]

    @State private var command = ""
    @State private var control = false

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                TaskTerminal(nas: nas, terminalId: terminalId, lines: 200, fontSize: 12)
            }
            .defaultScrollAnchor(.bottom)
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(paused ? Color.sageDeep : .clear, lineWidth: 2) }
            .padding(.horizontal, 16)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Button { control.toggle() } label: { key("ctrl", on: control) }
                    ForEach(Self.keys, id: \.name) { key in
                        Button { send { try await nas.terminalKeys(terminalId, keys: [key.name], literal: false) } } label: { self.key(key.label) }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 10) {
                Text("$").font(.body.monospaced().weight(.semibold)).foregroundStyle(.sageDeep)
                TextField("Type a command", text: $command)
                    .font(.system(.callout, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(run)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(.boneRaised, in: .capsule)
            .overlay { Capsule().strokeBorder(Color.sageLine, lineWidth: 1) }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func key(_ label: String, on: Bool = false) -> some View {
        Text(label)
            .font(.callout.monospaced().weight(.semibold))
            .foregroundStyle(.ink)
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 44)
            .background(.sage.opacity(on ? 0.32 : 0.14), in: .rect(cornerRadius: 12, style: .continuous))
    }

    /// Types the command line as it is, then presses Enter; with ctrl armed, its first letter goes as a Ctrl chord.
    private func run() {
        let line = command
        command = ""
        if control, let first = line.first, first.isLetter {
            control = false
            send { try await nas.terminalKeys(terminalId, keys: ["C-\(first.lowercased())"], literal: false) }
            return
        }
        send {
            if !line.isEmpty { try await nas.terminalKeys(terminalId, keys: [line], literal: true) }
            try await nas.terminalKeys(terminalId, keys: ["Enter"], literal: false)
        }
    }
}
