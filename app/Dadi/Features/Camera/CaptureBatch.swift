/// What the viewfinder has taken and where it goes. In single mode, the default, the first picture goes
/// straight to the message and the viewfinder closes; in multi mode pictures wait until the person is done.
struct CaptureBatch<Shot> {
    enum Mode: Equatable {
        case single, multi
    }

    private(set) var mode = Mode.single
    /// Pictures taken and not yet handed to the message.
    private(set) var held: [Shot] = []

    /// Switches between one picture and several. Pictures already held stay held.
    mutating func toggle() {
        mode = mode == .single ? .multi : .single
    }

    /// Takes `shot`. Returns the pictures to attach now, which closes the viewfinder, or nil to stay open.
    mutating func take(_ shot: Shot) -> [Shot]? {
        held.append(shot)
        return mode == .single ? finish() : nil
    }

    /// Hands over every held picture.
    mutating func finish() -> [Shot] {
        defer { held = [] }
        return held
    }
}
