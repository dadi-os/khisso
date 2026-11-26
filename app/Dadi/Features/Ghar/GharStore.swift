import SwiftUI

/// Ghar's devices and their tags for the Ghar pages, and every change made to them.
/// A command changes what the pages show at once and is put back, with Ghar's
/// reason, if Ghar refuses it; a rename or retag waits for Ghar's
/// answer. Every failure of a change is a toast on `toaster`, which the Ghar
/// pages show over their content.
@Observable @MainActor
final class GharStore {
    let ghar: GharClient

    private(set) var devices: [GharDevice] = []
    private(set) var loaded = false
    /// Why the last read of Ghar failed.
    private(set) var error: String?
    /// The failures of changes, which fade by themselves.
    let toaster = Toaster()
    /// Commands in flight per device. A read keeps the page's version of these
    /// devices so a light does not flicker back while Ghar is still switching it.
    private var inFlight: [String: Int] = [:]

    init(ghar: GharClient) {
        self.ghar = ghar
    }

    func device(_ id: String) -> GharDevice? { devices.first { $0.id == id } }

    /// The tag with this id, while any device carries it. Ghar drops a tag
    /// that no device has.
    func tag(_ id: String) -> GharDevice.Tag? {
        devices.lazy.flatMap(\.tags).first { $0.id == id }
    }

    /// The devices that carry the tag `id`, by name.
    func devices(tagged id: String) -> [GharDevice] {
        GharLayout.tags(devices).first { $0.id == id }?.devices ?? []
    }

    /// Reads every device and its tags from Ghar.
    func load() async {
        do {
            let nextDevices = try await ghar.devices()
            let local = Dictionary(uniqueKeysWithValues: devices.filter { inFlight[$0.id] != nil }.map { ($0.id, $0) })
            devices = nextDevices.map { local[$0.id] ?? $0 }
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
        run(answering(targets.filter { $0.has("on_off") })) { $0.with("on", .bool(on)) } commands: { _ in [on ? .on : .off] }
    }

    /// Sets every dimmable device in `targets` to `level`, which switches it on.
    func setLevel(_ level: Int, _ targets: [GharDevice]) {
        run(answering(targets.filter { $0.has("level") })) {
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

    /// Gives `device` exactly the tags named in `names`.
    @discardableResult
    func setTags(_ names: [String], on device: GharDevice) async -> Bool {
        await edit("Couldn't tag \(device.name)") {
            replace(try await ghar.update(device.id, GharDevicePatch(tags: names)))
        }
    }

    /// Puts `targets` under the tag named `name`, making the tag when no
    /// device has it yet.
    @discardableResult
    func addTag(_ name: String, to targets: [GharDevice]) async -> Bool {
        await edit("Couldn't tag \(name)") {
            let ids = targets.filter { !$0.tagNames.contains(name) }.map(\.id)
            guard !ids.isEmpty else { return }
            if let existing = devices.lazy.flatMap(\.tags).first(where: { $0.name == name }) {
                _ = try await ghar.add(ids, toTag: existing.id)
            } else {
                _ = try await ghar.createTag(named: name, devices: ids)
            }
            await load()
        }
    }

    /// Renames `device`.
    @discardableResult
    func rename(_ device: GharDevice, to name: String) async -> Bool {
        await edit("Couldn't rename \(device.name)") {
            replace(try await ghar.update(device.id, GharDevicePatch(name: name)))
        }
    }

    /// Renames the tag everywhere it is used.
    @discardableResult
    func rename(_ tag: GharDevice.Tag, to name: String) async -> Bool {
        await edit("Couldn't rename \(tag.name)") {
            _ = try await ghar.renameTag(tag.id, to: name)
            await load()
        }
    }

    /// Takes `tag` off every device that has it. The devices stay.
    @discardableResult
    func delete(_ tag: GharDevice.Tag) async -> Bool {
        await edit("Couldn't delete \(tag.name)") {
            try await ghar.deleteTag(tag.id)
            await load()
        }
    }

    /// Runs a registry change and toasts why it failed, under `label`.
    private func edit(_ label: String, _ change: () async throws -> Void) async -> Bool {
        do {
            try await change()
            return true
        } catch {
            toaster.show(Toast(key: "ghar-edit", title: label, detail: error.localizedDescription, symbol: ToastModule.ghar.symbol, failure: true))
            return false
        }
    }

    /// Why a command failed, and whether the device simply did not answer, which Ghar reports as 504.
    private struct Failure: Sendable {
        let reason: String
        let unreachable: Bool
    }

    /// Who is named when `names` cannot be reached: "Desk lamp is unreachable", "Desk lamp and Hall are unreachable".
    nonisolated static func unreachableTitle(_ names: [String]) -> String {
        switch names.count {
        case 1: "\(names[0]) is unreachable"
        case 2: "\(names[0]) and \(names[1]) are unreachable"
        default: "\(names.count) devices are unreachable"
        }
    }

    /// The toast for devices that did not take a change, with Ghar's reason when one answered.
    nonisolated static func refusedToast(_ failures: [(name: String, reason: String)]) -> Toast {
        let names = failures.map(\.name)
        return Toast(
            key: "ghar-refused",
            title: names.count == 1 ? "Couldn't change \(names[0])" : "Couldn't change \(names.count) devices",
            detail: failures.map { names.count == 1 ? $0.reason : "\($0.name): \($0.reason)" }.joined(separator: "\n"),
            symbol: ToastModule.ghar.symbol,
            failure: true
        )
    }

    private func showUnreachable(_ names: [String]) {
        toaster.show(Toast(key: "ghar-unreachable", title: Self.unreachableTitle(names), symbol: ToastModule.ghar.symbol, failure: true))
    }

    /// The part of `targets` that answers. When none does, the person is told who is unreachable, because
    /// nothing else will happen; when some do, the rest are left out quietly.
    private func answering(_ targets: [GharDevice]) -> [GharDevice] {
        let online = targets.filter(\.online)
        if online.isEmpty, !targets.isEmpty {
            showUnreachable(targets.map(\.name))
        }
        return online
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
            let failures = await withTaskGroup(of: (GharDevice, Failure?).self) { group in
                for job in jobs {
                    group.addTask {
                        do {
                            for command in job.commands {
                                try await ghar.send(command, to: job.before.id)
                            }
                            return (job.before, nil)
                        } catch {
                            return (job.before, Failure(reason: error.localizedDescription, unreachable: (error as? ServiceError)?.status == 504))
                        }
                    }
                }
                var failures: [(device: GharDevice, failure: Failure)] = []
                for await (device, failure) in group {
                    if let failure { failures.append((device, failure)) }
                }
                return failures
            }
            for job in jobs {
                let left = (inFlight[job.before.id] ?? 1) - 1
                inFlight[job.before.id] = left > 0 ? left : nil
            }
            withAnimation(Motion.snap) {
                for failure in failures { replace(failure.device) }
            }
            let silent = failures.filter(\.failure.unreachable)
            if !silent.isEmpty { showUnreachable(silent.map(\.device.name)) }
            let refused = failures.filter { !$0.failure.unreachable }
            if !refused.isEmpty { toaster.show(Self.refusedToast(refused.map { ($0.device.name, $0.failure.reason) })) }
            await load()
        }
    }

    private func replace(_ device: GharDevice) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index] = device
    }
}
