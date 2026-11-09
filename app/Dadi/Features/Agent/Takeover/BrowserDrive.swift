import SwiftUI

/// Queue of browser jobs for one browser: each runs when the one before it has finished, so a drag never
/// overtakes its own press. A failed job reports through `onError` and the ones behind it still run.
@MainActor
final class SerialQueue {
    private var jobs: [() async throws -> Void] = []
    private var running = false
    private let onError: (any Error) -> Void

    init(onError: @escaping (any Error) -> Void) {
        self.onError = onError
    }

    func push(_ job: @escaping () async throws -> Void) {
        jobs.append(job)
        drain()
    }

    private func drain() {
        guard !running, !jobs.isEmpty else { return }
        let job = jobs.removeFirst()
        running = true
        Task {
            do { try await job() } catch { onError(error) }
            running = false
            drain()
        }
    }
}

/// A browser filling its sheet at the drive profile. Watching, taps and keys do nothing; in control, a tap
/// clicks at the point touched, a drag scrolls, the keyboard types into the focused field, and back and reload
/// step through its history. What he does is recorded for the hand-back summary.
struct BrowserDrive: View {
    let nas: NasClient
    let browserId: Int
    let control: TakeoverControl

    /// Zero-width spaces under the hidden field, so a delete always changes it.
    private static let seed = String(repeating: "\u{200B}", count: 256)
    /// Points a touch may travel and still be a tap.
    private static let slop: CGFloat = 8
    /// The page's pixels a drag gathers before a wheel turn is sent.
    private static let wheelStep: Double = 24
    /// The display's size in page pixels at the drive profile, which wheel deltas are measured in.
    private static let page = (width: 1280.0, height: 720.0)

    @State private var typed = BrowserDrive.seed
    @State private var queue: SerialQueue
    @State private var scrollFrom: CGPoint?
    @FocusState private var keyboard: Bool

    init(nas: NasClient, browserId: Int, control: TakeoverControl) {
        self.nas = nas
        self.browserId = browserId
        self.control = control
        _queue = State(initialValue: SerialQueue { control.fail("The browser did not take that", $0) })
    }

    private var controlling: Bool { control.state == .inControl }

    var body: some View {
        VStack(spacing: 10) {
            BrowserView(nas: nas, browserId: browserId, profile: .drive)
                .overlay {
                    GeometryReader { geometry in
                        Color.clear
                            .contentShape(.rect)
                            .gesture(DragGesture(minimumDistance: 0).onChanged { scroll($0, in: geometry.size) }.onEnded { touch($0, in: geometry.size) })
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(controlling ? Color.sageDeep : .clear, lineWidth: 2) }
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
                .onSubmit { press(KeyFields(key: "Enter"), BrowserInputEvent.press(key: "Enter", code: "Enter", keyCode: 13, text: "\r")) }
            HStack {
                tool("chevron.left", "Back") { navigate("back", named: "Back") }
                tool("arrow.clockwise", "Reload") { navigate("reload", named: "Reload") }
                tool("keyboard", keyboard ? "Hide keyboard" : "Show keyboard") { keyboard.toggle() }
            }
            .disabled(!controlling)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .onChange(of: controlling) { _, now in if !now { keyboard = false } }
    }

    private func tool(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.ink)
        .accessibilityLabel(label)
    }

    /// A touch that ended: a tap when it did not travel, which clicks at that point; the end of a scroll otherwise.
    private func touch(_ drag: DragGesture.Value, in size: CGSize) {
        defer { scrollFrom = nil }
        guard scrollFrom == nil, hypot(drag.translation.width, drag.translation.height) < Self.slop, control.record(BrowserActivity.click) else { return }
        let x = fraction(drag.location.x, size.width)
        let y = fraction(drag.location.y, size.height)
        queue.push { try await nas.browserInput(browserId, events: [.pointer("move", x: x, y: y), .pointer("down", x: x, y: y), .pointer("up", x: x, y: y)]) }
    }

    /// A touch that moved: past the slop it scrolls the page by the distance dragged, a wheel turn for each `wheelStep` pixels.
    private func scroll(_ drag: DragGesture.Value, in size: CGSize) {
        guard controlling, size.width > 0, size.height > 0 else { return }
        if scrollFrom == nil {
            guard hypot(drag.translation.width, drag.translation.height) >= Self.slop else { return }
            _ = control.record(BrowserActivity.scroll)
            scrollFrom = drag.startLocation
        }
        guard let from = scrollFrom else { return }
        let deltaX = Double(from.x - drag.location.x) / size.width * Self.page.width
        let deltaY = Double(from.y - drag.location.y) / size.height * Self.page.height
        guard max(abs(deltaX), abs(deltaY)) >= Self.wheelStep else { return }
        scrollFrom = drag.location
        let x = fraction(drag.location.x, size.width)
        let y = fraction(drag.location.y, size.height)
        queue.push { try await nas.browserInput(browserId, events: [.wheel(x: x, y: y, deltaX: deltaX, deltaY: deltaY)]) }
    }

    private func fraction(_ point: CGFloat, _ length: CGFloat) -> Double {
        Double(min(max(point / length, 0), 1))
    }

    /// Records `keys` and sends `events` while in control.
    private func press(_ keys: KeyFields, _ events: [BrowserInputEvent]) {
        guard let activity = browserKeyActivity(keys), control.record(activity) else { return }
        queue.push { try await nas.browserInput(browserId, events: events) }
    }

    private func navigate(_ action: String, named name: String) {
        guard control.record(BrowserActivity.key(name)) else { return }
        queue.push { try await nas.browserNavigate(browserId, action: action) }
    }

    /// Sends what the keyboard added to or took from the hidden field as key presses.
    private func type(from old: String, to new: String) {
        if new.count > old.count {
            for character in new.dropFirst(old.count) {
                let text = String(character)
                press(KeyFields(key: text), BrowserInputEvent.press(key: text, code: "", keyCode: Int(text.uppercased().unicodeScalars.first?.value ?? 0), text: text))
            }
        } else {
            for _ in 0..<(old.count - new.count) { press(KeyFields(key: "Backspace"), BrowserInputEvent.press(key: "Backspace", code: "Backspace", keyCode: 8)) }
        }
    }
}
