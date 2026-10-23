import SwiftUI

/// One device as a tile, the only card on the Ghar pages. A lit light's tile
/// takes its color, as strong as it is bright, with the icon disc in the full
/// color; an off tile is quiet bone with a hairline.
struct LightTile: View {
    let device: GharDevice
    var height: CGFloat = 124

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let on = device.isOn == true && device.online
        let light = GharLayout.color(device)
        let strength = device.has("level") ? (device.number("brightness") ?? 100) / 100 : 1
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: GharLayout.symbol(device.kind, on: on))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(on ? light.mixed(with: .black, by: 0.65).color : Color.inkFaint)
                .symbolEffect(.bounce, value: on)
                .frame(width: 40, height: 40)
                .background(on ? light.color : Color.boneDeep, in: .circle)
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(GharLayout.status(device))
                    .font(.system(size: 13))
                    .foregroundStyle(on ? GharInk.soft(light, scheme) : Color.inkMuted)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: .infinity, alignment: .leading)
        .background(on ? light.color.opacity(0.14 + 0.22 * strength) : Color.bone, in: shape)
        .overlay(shape.strokeBorder(on ? light.color.opacity(0.55 + 0.4 * strength) : Color.rule, lineWidth: 1))
        .opacity(device.online ? 1 : 0.55)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: device.state)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to switch. Hold for its controls.")
    }
}

/// Text inks drawn from a light's color, for text sitting on that light.
enum GharInk {
    /// Secondary text: the light's own color darkened, or lightened in Dark
    /// Mode.
    static func soft(_ light: LightColor, _ scheme: ColorScheme) -> Color {
        scheme == .dark ? light.mixed(with: .white, by: 0.35).color : light.mixed(with: .black, by: 0.58).color
    }

    /// Primary text on a fill of the light's color.
    static func deep(_ light: LightColor) -> Color {
        light.mixed(with: .black, by: 0.77).color
    }
}

/// The Ghar switch: a sage track with a white knob that slides across, with a
/// tap of haptic feedback.
struct GharSwitch: View {
    let isOn: Bool
    let label: String
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Capsule()
                .fill(isOn ? (scheme == .dark ? Color.sage : .sageDeep) : Color.inkFaint.opacity(0.6))
                .frame(width: 54, height: 32)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 26, height: 26)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .padding(3)
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isOn)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A room's or group's brightness as a bar on the field, filled in its mixed
/// light. Dragging sets every light at once; the bar follows the finger and
/// sends the level when let go.
struct LevelBar: View {
    let summary: GharSummary
    let commit: (Int) -> Void

    @State private var dragging: Double?

    var body: some View {
        let lit = summary.on > 0
        let level = dragging ?? Double(lit ? summary.level ?? 100 : 0)
        let fill = (summary.color ?? .white(kelvin: 2700)).color
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.rule)
                Rectangle()
                    .fill(fill.opacity(0.55))
                    .frame(width: proxy.size.width * level / 100)
                Label {
                    Text(dragging != nil || lit ? "Brightness · \(Int(level))%" : "Brightness · Off")
                        .contentTransition(.numericText())
                } icon: {
                    Image(systemName: "sun.max")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.ink)
                .padding(.leading, 16)
            }
            .clipShape(.capsule)
            .contentShape(.capsule)
            .animation(dragging == nil ? Motion.snap : nil, value: level)
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { drag in dragging = min(100, max(1, drag.location.x / proxy.size.width * 100)) }
                    .onEnded { _ in
                        if let dragging { commit(Int(dragging.rounded())) }
                        dragging = nil
                    }
            )
        }
        .frame(height: 46)
        .sensoryFeedback(.selection, trigger: Int(level / 10))
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue(lit ? "\(Int(level)) percent" : "Off")
        .accessibilityAdjustableAction { direction in
            commit(Int(min(100, max(1, level + (direction == .increment ? 10 : -10)))))
        }
    }
}

/// A chip on the field: bone text when chosen (the caller lays the sage fill
/// under it, so the fill can slide between chips), outlined otherwise, dashed
/// for one that makes something new.
struct GharChip: View {
    let title: String
    var symbol: String?
    var selected = false
    var dashed = false
    var height: CGFloat = 34

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 13, weight: selected || dashed ? .semibold : .medium))
                .lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(selected ? Color.bone : .sageDeep)
        .padding(.horizontal, 14)
        .frame(height: height)
        .overlay {
            if dashed {
                shape.strokeBorder(Color.sageLine, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            } else if !selected {
                shape.strokeBorder(Color.sageLine.opacity(0.7), lineWidth: 1)
            }
        }
        .contentShape(shape)
    }
}

/// A rounded action on the field: bone with a sage hairline, or filled sage
/// for the main one.
struct GharButtonStyle: ButtonStyle {
    var prominent = false
    var height: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(prominent ? Color.bone : .ink)
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(prominent ? Color.sageDeep : .bone, in: .capsule)
            .overlay {
                if !prominent { Capsule().strokeBorder(Color.sageLine, lineWidth: 1) }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.snap, value: configuration.isPressed)
    }
}

/// A sheet for choosing devices: lights to move into a room, or the lights
/// of a new group with its name. It stays open with Ghar's reason when Ghar
/// refuses.
struct DevicePicker: View {
    let store: GharStore
    let title: String
    let action: String
    let devices: [GharDevice]
    /// The name field's prompt; nil leaves the field out.
    var naming: String?
    let done: (_ name: String, _ chosen: [GharDevice]) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []
    @State private var name = ""
    @State private var working = false

    var body: some View {
        let ready = !chosen.isEmpty && (naming == nil || !trimmed.isEmpty) && !working
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.ink)
            if let naming {
                TextField(naming, text: $name)
                    .font(.system(size: 15))
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .overlay(Capsule().strokeBorder(Color.sageLine, lineWidth: 1))
            }
            if devices.isEmpty {
                Text("There are no other devices to choose.")
                    .font(.system(size: 15))
                    .foregroundStyle(.inkMuted)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(devices) { device in
                        let picked = chosen.contains(device.id)
                        Button {
                            withAnimation(Motion.snap) {
                                if picked { chosen.remove(device.id) } else { chosen.insert(device.id) }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: GharLayout.symbol(device.kind, on: false))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.inkMuted)
                                    .frame(width: 34, height: 34)
                                    .background(Color.boneDeep, in: .circle)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(device.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.ink)
                                    Text(GharLayout.name(of: device.room)).font(.system(size: 13)).foregroundStyle(.inkMuted)
                                }
                                Spacer()
                                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(picked ? Color.sageDeep : .inkFaint)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .frame(height: 56)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: picked)
                        Divider().overlay(Color.rule)
                    }
                }
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
            if let problem = store.problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
            }
            Button {
                working = true
                Task {
                    let picked = devices.filter { chosen.contains($0.id) }
                    if await done(trimmed, picked) { dismiss() }
                    working = false
                }
            } label: {
                Text(working ? "Working…" : action).frame(maxWidth: .infinity)
            }
            .buttonStyle(GharButtonStyle(prominent: true, height: 46))
            .disabled(!ready)
            .opacity(ready ? 1 : 0.5)
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 22)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}
