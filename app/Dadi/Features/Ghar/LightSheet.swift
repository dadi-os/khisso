import SwiftUI

/// One light's sheet: its switch, a tall brightness pill, warmth and color
/// sliders, preset swatches, and which room and groups it is in. Tap the name
/// to rename it.
struct LightSheet: View {
    let store: GharStore
    let deviceId: String

    @State private var renaming = false
    @State private var naming = false
    @State private var name = ""
    @State private var group = ""

    var body: some View {
        if let device = store.device(deviceId) {
            content(device)
        }
    }

    private func content(_ device: GharDevice) -> some View {
        let modes = device.colorModes
        let presets = LightPreset.all.filter { preset in
            switch preset.setting {
            case .white: modes.contains("color_temp")
            case .hue: modes.contains("hue_sat")
            }
        }
        return VStack(spacing: 0) {
            HStack {
                Button {
                    name = device.name
                    renaming = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.ink)
                        Text([GharLayout.name(of: device.room), device.productName].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 13))
                            .foregroundStyle(.inkMuted)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Renames the light")
                Spacer()
                if device.has("on_off") {
                    GharSwitch(isOn: device.isOn == true, label: "Switch \(device.name)") { store.toggle(device) }
                        .disabled(!device.online)
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 4)

            if device.has("level") {
                BrightnessPill(device: device) { store.setLevel($0, [device]) }
                    .padding(.top, 22)
                    .padding(.bottom, 18)
            }

            if modes.contains("color_temp") {
                let range = GharLayout.warmthRange
                let warmth = (1_000_000 / (device.number("color_temp") ?? Double(GharLayout.eveningMireds)) - range.lowerBound) / (range.upperBound - range.lowerBound)
                GradientSlider(
                    title: "Warmth",
                    fraction: warmth,
                    colors: [Color(red: 1, green: 0.706, blue: 0.420), Color(red: 1, green: 0.906, blue: 0.769), Color(red: 0.957, green: 0.969, blue: 1), Color(red: 0.788, green: 0.855, blue: 1)]
                ) { fraction in
                    "\(Int((Self.kelvin(fraction ?? warmth) / 100).rounded()) * 100) K"
                } commit: { fraction in
                    store.setWhite(mireds: Int(min(500, max(153, 1_000_000 / Self.kelvin(fraction)))), device)
                }
            }

            if modes.contains("hue_sat") {
                GradientSlider(
                    title: "Color",
                    fraction: (device.number("hue") ?? 0) / 254,
                    colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { LightColor.hue($0 * 254, saturation: 254).color }
                ) { fraction in
                    if let fraction { return GharLayout.hueName(fraction * 254, saturation: 254) }
                    return GharLayout.colorName(device) ?? "Color"
                } commit: { fraction in
                    store.setHue(Int((fraction * 254).rounded()), saturation: 254, device)
                }
                .padding(.top, 16)
            }

            if !presets.isEmpty {
                HStack(spacing: 12) {
                    ForEach(presets) { preset in
                        let current = preset.matches(device)
                        Button { store.apply(preset, to: device) } label: {
                            Circle()
                                .fill(preset.swatch)
                                .frame(width: 44, height: 44)
                                .overlay(Circle().strokeBorder(current ? Color.sageDeep : .rule, lineWidth: current ? 2 : 1))
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: current)
                        .accessibilityLabel(preset.name)
                        .accessibilityAddTraits(current ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 18)
                .animation(Motion.snap, value: device.state)
            }

            if let problem = store.problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
            }

            VStack(spacing: 0) {
                Divider().overlay(Color.rule)
                roomRow(device)
                Divider().overlay(Color.rule)
                groupsRow(device)
            }
            .padding(.top, 26)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 26)
        .alert("Rename light", isPresented: $renaming) {
            TextField("Light name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let next = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !next.isEmpty, next != device.name else { return }
                Task { await store.rename(device, to: next) }
            }
        }
        .alert("New group", isPresented: $naming) {
            TextField("Group name, like Nightstands", text: $group)
            Button("Cancel", role: .cancel) { group = "" }
            Button("Add") {
                let next = group.trimmingCharacters(in: .whitespacesAndNewlines)
                group = ""
                guard !next.isEmpty, !device.groups.contains(next) else { return }
                Task { await store.setGroups(device.groups + [next], on: device) }
            }
        } message: {
            Text("\(device.name) joins the new group.")
        }
    }

    /// The Room row: a menu of every room that moves the light there.
    private func roomRow(_ device: GharDevice) -> some View {
        let rooms = store.rooms.sorted { ($0.name == GharLayout.unassigned ? 1 : 0, $0.name) < ($1.name == GharLayout.unassigned ? 1 : 0, $1.name) }
        return Menu {
            Picker("Room", selection: Binding(get: { device.room.id }, set: { id in
                guard let room = store.room(id), id != device.room.id else { return }
                Task { await store.move([device], to: room) }
            })) {
                ForEach(rooms) { room in
                    Text(GharLayout.name(of: room)).tag(room.id)
                }
            }
        } label: {
            row("Room", value: GharLayout.name(of: device.room))
        }
    }

    /// The Groups row: a menu that adds the light to a group or takes it out,
    /// or makes a new group with it.
    private func groupsRow(_ device: GharDevice) -> some View {
        Menu {
            ForEach(GharLayout.groups(store.devices)) { candidate in
                Toggle(candidate.name, isOn: Binding(get: { device.groups.contains(candidate.name) }, set: { joined in
                    let next = joined ? device.groups + [candidate.name] : device.groups.filter { $0 != candidate.name }
                    Task { await store.setGroups(next, on: device) }
                }))
            }
            Divider()
            Button("New group…", systemImage: "plus") { naming = true }
        } label: {
            row("Groups", value: device.groups.isEmpty ? "None" : device.groups.joined(separator: ", "))
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.ink)
            Spacer()
            Text("\(value) ›").foregroundStyle(.inkMuted).lineLimit(1)
        }
        .font(.system(size: 15))
        .frame(height: 52)
        .contentShape(.rect)
    }

    /// The white on the warmth slider at `fraction`, warm on the left.
    private static func kelvin(_ fraction: Double) -> Double {
        GharLayout.warmthRange.lowerBound + fraction * (GharLayout.warmthRange.upperBound - GharLayout.warmthRange.lowerBound)
    }
}

/// A tall Control Center–style pill that fills from the bottom in the light's
/// color as you drag it. It follows the finger and sends the level when let
/// go, which also switches the light on.
private struct BrightnessPill: View {
    let device: GharDevice
    let commit: (Int) -> Void

    @State private var dragging: Double?

    var body: some View {
        let on = device.isOn == true
        let light = GharLayout.color(device)
        let level = dragging ?? (on ? device.number("brightness") ?? 100 : 0)
        let lit = on || dragging != nil
        let shape = RoundedRectangle(cornerRadius: 40, style: .continuous)
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color.rule)
                Rectangle()
                    .fill(light.color)
                    .frame(height: proxy.size.height * level / 100)
                VStack(spacing: 4) {
                    Image(systemName: lit ? "sun.max" : "sun.min")
                        .font(.system(size: 22, weight: .semibold))
                    Text(lit ? "\(Int(level))%" : "Off")
                        .font(.system(size: 20, weight: .bold))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(lit && level >= 22 ? GharInk.deep(light) : Color.ink)
                .padding(.bottom, 18)
            }
            .clipShape(shape)
            .contentShape(shape)
            .animation(dragging == nil ? Motion.settle : nil, value: level)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in dragging = min(100, max(1, (1 - drag.location.y / proxy.size.height) * 100)) }
                    .onEnded { _ in
                        if let dragging { commit(Int(dragging.rounded())) }
                        dragging = nil
                    }
            )
        }
        .frame(width: 128, height: 276)
        .sensoryFeedback(.selection, trigger: Int(level / 10))
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue(on ? "\(Int(level)) percent" : "Off")
        .accessibilityAdjustableAction { direction in
            commit(Int(min(100, max(1, level + (direction == .increment ? 10 : -10)))))
        }
    }
}

/// A slider drawn as a gradient track with a white knob. It follows the
/// finger and calls `commit` with the fraction when let go; `value` names the
/// setting, given the fraction under the finger while dragging.
private struct GradientSlider: View {
    let title: String
    let fraction: Double
    let colors: [Color]
    let value: (Double?) -> String
    let commit: (Double) -> Void

    @State private var dragging: Double?

    var body: some View {
        let shown = min(1, max(0, dragging ?? fraction))
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).foregroundStyle(.sageDeep)
                Spacer()
                Text(value(dragging)).foregroundStyle(.inkMuted).contentTransition(.numericText())
            }
            .font(.system(size: 13, weight: .semibold))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    Circle()
                        .fill(.white)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: 3 + shown * (proxy.size.width - 30))
                }
                .contentShape(.capsule)
                .animation(dragging == nil ? Motion.snap : nil, value: shown)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in dragging = min(1, max(0, (drag.location.x - 15) / (proxy.size.width - 30))) }
                        .onEnded { _ in
                            if let dragging { commit(dragging) }
                            dragging = nil
                        }
                )
            }
            .frame(height: 30)
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(value(nil))
        .accessibilityAdjustableAction { direction in
            commit(min(1, max(0, shown + (direction == .increment ? 0.1 : -0.1))))
        }
    }
}
