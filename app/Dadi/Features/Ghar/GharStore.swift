import SwiftUI

/// Ghar's devices and rooms for the Ghar pages, and every change made to them.
/// A command changes what the pages show at once and is put back, with Ghar's
/// reason, if Ghar refuses it; a move, rename or regroup waits for Ghar's
/// answer.
@Observable @MainActor
final class GharStore {
    let ghar: GharClient

    private(set) var devices: [GharDevice] = []
    private(set) var rooms: [GharRoom] = []
    private(set) var loaded = false
    /// Why the last read of Ghar failed.
    private(set) var error: String?
    /// Why the last change failed. It stays until a change succeeds or it is
    /// dismissed.
    var problem: String?
    /// Commands in flight per device. A read keeps the page's version of these
    /// devices so a light does not flicker back while Ghar is still switching it.
    private var inFlight: [String: Int] = [:]

    init(ghar: GharClient) {
        self.ghar = ghar
    }

    func device(_ id: String) -> GharDevice? { devices.first { $0.id == id } }

    func room(_ id: String) -> GharRoom? { rooms.first { $0.id == id } }

    /// Reads every device and room from Ghar.
    func load() async {
        do {
            async let fetchedDevices = ghar.devices()
            async let fetchedRooms = ghar.rooms()
            let (nextDevices, nextRooms) = try await (fetchedDevices, fetchedRooms)
            let local = Dictionary(uniqueKeysWithValues: devices.filter { inFlight[$0.id] != nil }.map { ($0.id, $0) })
            devices = nextDevices.map { local[$0.id] ?? $0 }
            rooms = nextRooms
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    /// Switches `device` the other way.
    func toggle(_ device: GharDevice) {
        setOn(!(device.isOn ?? false), [device])
    }

    /// Switches every device in `targets` that switches and answers.
    func setOn(_ on: Bool, _ targets: [GharDevice]) {
        run(targets.filter { $0.has("on_off") && $0.online }) { $0.with("on", .bool(on)) } commands: { _ in [on ? .on : .off] }
    }

    /// Sets every dimmable device in `targets` to `level`, which switches it on.
    func setLevel(_ level: Int, _ targets: [GharDevice]) {
        run(targets.filter { $0.has("level") && $0.online }) {
            $0.with("brightness", .number(Double(level))).with("on", .bool(level > 0))
        } commands: { _ in [.level(level)] }
    }

    /// Sets `device` to a white of `mireds`.
    func setWhite(mireds: Int, _ device: GharDevice) {
        run([device]) {
            $0.with("color_temp", .number(Double(mireds))).with("color_mode", .string("color_temp"))
        } commands: { _ in [.temperature(mireds: mireds)] }
    }

    /// Sets `device` to a color on Matter's 0–254 hue and saturation scales.
    func setHue(_ hue: Int, saturation: Int, _ device: GharDevice) {
        run([device]) {
            $0.with("hue", .number(Double(hue))).with("saturation", .number(Double(saturation))).with("color_mode", .string("hue_sat"))
        } commands: { _ in [.hue(hue, saturation: saturation)] }
    }

    /// Sets `device` to one of the light sheet's presets.
    func apply(_ preset: LightPreset, to device: GharDevice) {
        switch preset.setting {
        case .white(let mireds): setWhite(mireds: mireds, device)
        case .hue(let hue, let saturation): setHue(hue, saturation: saturation, device)
        }
    }

    /// Evening: every light on, dimmed and warm. The white is set first so a
    /// light that was off comes on already warm.
    func evening() {
        let lights = devices.filter { $0.kind == "light" && $0.has("on_off") && $0.online }
        run(lights) { light in
            var next = light.with("on", .bool(true))
            if light.has("level") { next = next.with("brightness", .number(Double(GharLayout.eveningLevel))) }
            if light.colorModes.contains("color_temp") {
                next = next.with("color_temp", .number(Double(GharLayout.eveningMireds))).with("color_mode", .string("color_temp"))
            }
            return next
        } commands: { light in
            let white: [GharCommand] = light.colorModes.contains("color_temp") ? [.temperature(mireds: GharLayout.eveningMireds)] : []
            return white + [light.has("level") ? .level(GharLayout.eveningLevel) : .on]
        }
    }

    /// Moves `targets` into `room`, stopping at the first one Ghar refuses.
    @discardableResult
    func move(_ targets: [GharDevice], to room: GharRoom) async -> Bool {
        await edit("Couldn't move to \(GharLayout.name(of: room))") {
            for target in targets {
                replace(try await ghar.update(target.id, GharDevicePatch(room: room.id)))
            }
        }
    }

    /// Gives `device` exactly the groups in `groups`.
    @discardableResult
    func setGroups(_ groups: [String], on device: GharDevice) async -> Bool {
        await edit(device.name) {
            replace(try await ghar.update(device.id, GharDevicePatch(tags: groups)))
        }
    }

    /// Adds `group` to every device in `targets`.
    @discardableResult
    func addGroup(_ group: String, to targets: [GharDevice]) async -> Bool {
        await edit("Couldn't make \(group)") {
            for target in targets where !target.groups.contains(group) {
                replace(try await ghar.update(target.id, GharDevicePatch(tags: target.groups + [group])))
            }
        }
    }

    /// Renames `device`.
    @discardableResult
    func rename(_ device: GharDevice, to name: String) async -> Bool {
        await edit(device.name) {
            replace(try await ghar.update(device.id, GharDevicePatch(name: name)))
        }
    }

    /// Makes a room named `name`.
    @discardableResult
    func createRoom(named name: String) async -> Bool {
        await edit("Couldn't make \(name)") {
            rooms.append(try await ghar.createRoom(named: name))
        }
    }

    /// Renames `room`.
    @discardableResult
    func rename(_ room: GharRoom, to name: String) async -> Bool {
        await edit(room.name) {
            let renamed = try await ghar.renameRoom(room.id, to: name)
            rooms = rooms.map { $0.id == renamed.id ? renamed : $0 }
            await load()
        }
    }

    /// Deletes `room`. Ghar refuses a room that still has devices.
    @discardableResult
    func delete(_ room: GharRoom) async -> Bool {
        await edit("Couldn't delete \(room.name)") {
            try await ghar.deleteRoom(room.id)
            rooms.removeAll { $0.id == room.id }
        }
    }

    /// Runs a registry change and shows why it failed, under `label`.
    private func edit(_ label: String, _ change: () async throws -> Void) async -> Bool {
        do {
            try await change()
            withAnimation(Motion.snap) { problem = nil }
            return true
        } catch {
            withAnimation(Motion.snap) { problem = "\(label): \(error.localizedDescription)" }
            return false
        }
    }

    /// Shows each target changed at once, sends its commands in order, and
    /// puts back every target Ghar refuses, naming it and Ghar's reason.
    private func run(_ targets: [GharDevice], change: (GharDevice) -> GharDevice, commands: (GharDevice) -> [GharCommand]) {
        guard !targets.isEmpty else { return }
        let jobs = targets.map { (before: $0, commands: commands($0)) }
        for target in targets {
            replace(change(target))
            inFlight[target.id, default: 0] += 1
        }
        let ghar = ghar
        Task {
            let failures = await withTaskGroup(of: (GharDevice, String?).self) { group in
                for job in jobs {
                    group.addTask {
                        do {
                            for command in job.commands {
                                try await ghar.send(command, to: job.before.id)
                            }
                            return (job.before, nil)
                        } catch {
                            return (job.before, error.localizedDescription)
                        }
                    }
                }
                var failures: [(device: GharDevice, reason: String)] = []
                for await (device, reason) in group {
                    if let reason { failures.append((device, reason)) }
                }
                return failures
            }
            for job in jobs {
                let left = (inFlight[job.before.id] ?? 1) - 1
                inFlight[job.before.id] = left > 0 ? left : nil
            }
            withAnimation(Motion.snap) {
                for failure in failures { replace(failure.device) }
                problem = failures.isEmpty ? nil : failures.map { "\($0.device.name): \($0.reason)" }.joined(separator: "\n")
            }
            await load()
        }
    }

    private func replace(_ device: GharDevice) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index] = device
    }
}
