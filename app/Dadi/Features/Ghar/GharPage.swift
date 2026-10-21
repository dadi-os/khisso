import SwiftUI

/// Ghar: every device by room as glass tiles. A light that's on glows in its
/// own color and brightness. Tap a tile to switch it; press and hold for its
/// controls. Ghar is asked again every few seconds while the page is open, so
/// changes made elsewhere show up.
struct GharPage: View {
    let ghar: GharClient

    @State private var devices: [GharDevice] = []
    @State private var rooms: [GharRoom] = []
    @State private var room: String?
    @State private var error: String?
    @State private var loaded = false
    @State private var focused: GharDevice?
    @State private var pending: Set<String> = []
    @State private var switched = 0
    @Namespace private var chip

    /// How often the page asks Ghar for fresh state.
    private let refresh: Duration = .seconds(4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                roomChips
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.danger)
                }
                if loaded && shown.isEmpty && error == nil {
                    ContentUnavailableView("No devices here", systemImage: "house", description: Text("Add devices from the Ghar page on your Mac or the box."))
                        .foregroundStyle(.inkMuted)
                        .padding(.top, 40)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(shown) { device in
                        DeviceTile(device: device, busy: pending.contains(device.id))
                            .onTapGesture { toggle(device) }
                            .onLongPressGesture(minimumDuration: 0.35) { focused = device }
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .animation(Motion.settle, value: shown)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await load() }
        .sensoryFeedback(.impact(weight: .medium), trigger: switched)
        .sheet(item: $focused) { device in
            DeviceControls(ghar: ghar, deviceId: device.id, devices: $devices)
                .presentationDetents([.medium, .large])
                .presentationBackground(.thinMaterial)
        }
        .navigationTitle("Ghar")
        .task {
            while !Task.isCancelled {
                await load()
                do { try await Task.sleep(for: refresh) } catch { return }
            }
        }
    }

    /// Devices in the chosen room, or all of them, by room then name.
    private var shown: [GharDevice] {
        devices
            .filter { room == nil || $0.room.id == room }
            .sorted { ($0.room.name, $0.name) < ($1.room.name, $1.name) }
    }

    private var roomChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                roomChip(nil, title: "Everywhere")
                ForEach(rooms.filter { candidate in devices.contains { $0.room.id == candidate.id } }) { candidate in
                    roomChip(candidate.id, title: candidate.name == "unassigned" ? "Unplaced" : candidate.name)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func roomChip(_ id: String?, title: String) -> some View {
        let selected = room == id
        return Button {
            withAnimation(Motion.snap) { room = id }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.bone : .ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule().fill(.sageDeep).matchedGeometryEffect(id: "chip", in: chip)
                    }
                }
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .identity : .regular, in: .capsule)
    }

    private func load() async {
        do {
            async let fetchedDevices = ghar.devices()
            async let fetchedRooms = ghar.rooms()
            let (nextDevices, nextRooms) = try await (fetchedDevices, fetchedRooms)
            devices = nextDevices.filter { !pending.contains($0.id) } + devices.filter { pending.contains($0.id) }
            rooms = nextRooms
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    /// Switches a device and shows Ghar's answer; a failure shows its reason.
    private func toggle(_ device: GharDevice) {
        guard device.online, device.has("on_off"), !pending.contains(device.id) else {
            if device.has("level") || device.has("color") { focused = device }
            return
        }
        pending.insert(device.id)
        switched += 1
        Task {
            defer { pending.remove(device.id) }
            do {
                try await ghar.send(.toggle, to: device.id)
                devices = try await ghar.devices()
                error = nil
            } catch {
                withAnimation(Motion.snap) { self.error = "\(device.name): \(error.localizedDescription)" }
            }
        }
    }
}

/// One device as a glass tile: its icon, name, room and state, glowing in its
/// light's color when it is on.
private struct DeviceTile: View {
    let device: GharDevice
    let busy: Bool

    var body: some View {
        let on = device.isOn ?? false
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: GharStyle.symbol(device.kind, on: on))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(on ? GharStyle.glow(device) : .inkMuted)
                    .symbolEffect(.bounce, value: on)
                    .frame(width: 44, height: 44)
                    .background((on ? GharStyle.glow(device) : Color.inkFaint).opacity(on ? 0.22 : 0.12), in: .circle)
                Spacer()
                if busy {
                    ProgressView().controlSize(.small)
                } else if !device.online {
                    Image(systemName: "wifi.slash").font(.caption).foregroundStyle(.inkFaint)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ink)
                    .lineLimit(2)
                Text(GharStyle.status(device))
                    .font(.footnote)
                    .foregroundStyle(on ? Color.sageText : .inkMuted)
                    .contentTransition(.numericText())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(on ? AnyShapeStyle(RadialGradient(colors: [GharStyle.glow(device).opacity(0.38), GharStyle.glow(device).opacity(0.06)], center: .topLeading, startRadius: 0, endRadius: 220)) : AnyShapeStyle(Color.clear))
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        .opacity(device.online ? 1 : 0.55)
        .animation(Motion.settle, value: on)
        .contentShape(.rect(cornerRadius: 26))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to switch. Hold for controls.")
    }
}

/// A device's controls in a sheet: power, a tall brightness pill, warmth and
/// color for lights.
private struct DeviceControls: View {
    let ghar: GharClient
    let deviceId: String
    @Binding var devices: [GharDevice]

    @State private var brightness: Double = 100
    @State private var mireds: Double = 300
    @State private var hue: Double = 0
    @State private var problem: String?

    private var device: GharDevice? { devices.first { $0.id == deviceId } }

    var body: some View {
        if let device {
            VStack(spacing: 22) {
                VStack(spacing: 4) {
                    Text(device.name).font(.title3.weight(.semibold)).foregroundStyle(.ink)
                    Text([device.room.name == "unassigned" ? "Unplaced" : device.room.name, device.productName].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                }
                HStack(alignment: .bottom, spacing: 26) {
                    if device.has("level") {
                        BrightnessPill(value: $brightness, glow: GharStyle.glow(device), on: device.isOn ?? false) { send(.level(Int($0))) }
                    }
                    if device.has("on_off") {
                        Button { send(.toggle) } label: {
                            Image(systemName: "power")
                                .font(.title.weight(.semibold))
                                .frame(width: 64, height: 64)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint((device.isOn ?? false) ? Color.sageDeep : .inkFaint)
                    }
                }
                let modes = device.config("color")?["modes"]?.array?.compactMap(\.string) ?? []
                if modes.contains("color_temp") {
                    GradientSlider(title: "Warmth", value: $mireds, range: 153...500, colors: [Color(red: 0.85, green: 0.92, blue: 1), Color(red: 1, green: 0.76, blue: 0.45)]) { send(.temperature(mireds: Int($0))) }
                }
                if modes.contains("hue_sat") {
                    GradientSlider(title: "Color", value: $hue, range: 0...254, colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]) {
                        send(.hue(Int($0), saturation: Int(device.number("saturation") ?? 254)))
                    }
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.danger)
                }
            }
            .padding(24)
            .onAppear {
                brightness = device.number("brightness") ?? 100
                mireds = device.number("color_temp") ?? 300
                hue = device.number("hue") ?? 0
            }
        }
    }

    private func send(_ command: GharCommand) {
        Task {
            do {
                try await ghar.send(command, to: deviceId)
                devices = try await ghar.devices()
                problem = nil
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}

/// A tall Control Center–style pill that fills with light as you drag it.
private struct BrightnessPill: View {
    @Binding var value: Double
    let glow: Color
    let on: Bool
    let commit: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 32, style: .continuous).fill(.inkFaint.opacity(0.18))
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(LinearGradient(colors: [glow.opacity(on ? 0.95 : 0.4), glow.opacity(on ? 0.6 : 0.25)], startPoint: .top, endPoint: .bottom))
                    .frame(height: proxy.size.height * value / 100)
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(.bone)
                    .padding(.bottom, 18)
            }
            .clipShape(.rect(cornerRadius: 32, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in value = min(100, max(1, (1 - drag.location.y / proxy.size.height) * 100)) }
                    .onEnded { _ in commit(value) }
            )
        }
        .frame(width: 96, height: 210)
        .sensoryFeedback(.selection, trigger: Int(value / 10))
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int(value)) percent")
        .accessibilityAdjustableAction { direction in
            value = min(100, max(1, value + (direction == .increment ? 10 : -10)))
            commit(value)
        }
    }
}

/// A slider drawn as a gradient track with a glass thumb.
private struct GradientSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let colors: [Color]
    let commit: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.inkMuted)
            GeometryReader { proxy in
                let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    Circle()
                        .fill(.white)
                        .frame(width: 30, height: 30)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                        .offset(x: fraction * (proxy.size.width - 30))
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let f = min(1, max(0, (drag.location.x - 15) / (proxy.size.width - 30)))
                            value = range.lowerBound + f * (range.upperBound - range.lowerBound)
                        }
                        .onEnded { _ in commit(value) }
                )
            }
            .frame(height: 30)
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 10
            value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? step : -step)))
            commit(value)
        }
    }
}

/// How Ghar devices look: a symbol per kind, the glow of a light, a status line.
enum GharStyle {
    static func symbol(_ kind: String, on: Bool) -> String {
        switch kind {
        case "light": on ? "lightbulb.fill" : "lightbulb"
        case "plug": "powerplug.fill"
        case "switch": "switch.2"
        case "fan", "air_purifier": "fan.fill"
        case "thermostat", "air_conditioner", "heat_pump": "thermometer.medium"
        case "lock": "lock.fill"
        case "cover": "blinds.horizontal.closed"
        case "contact": "sensor.fill"
        case "occupancy": "figure.walk.motion"
        case "temperature": "thermometer"
        case "humidity": "humidity.fill"
        case "speaker": "hifispeaker.fill"
        case "tv": "tv.fill"
        case "camera", "doorbell": "video.fill"
        case "robot_vacuum": "fan.ceiling.fill"
        default: "circle.grid.2x2.fill"
        }
    }

    /// A light's current color from its hue and saturation or white
    /// temperature; dadi's clay glow for everything else.
    static func glow(_ device: GharDevice) -> Color {
        guard device.kind == "light" else { return .clay }
        if device.state["color_mode"]?.value.string == "hue_sat", let hue = device.number("hue"), let sat = device.number("saturation") {
            return Color(hue: hue / 254, saturation: max(0.25, sat / 254), brightness: 1)
        }
        if let mireds = device.number("color_temp") {
            let warm = (mireds - 153) / (500 - 153)
            return Color(red: 1, green: 0.95 - warm * 0.2, blue: 0.9 - warm * 0.5)
        }
        return Color(red: 1, green: 0.85, blue: 0.6)
    }

    /// "On · 80%", "Off", "Offline", or a sensor's reading.
    static func status(_ device: GharDevice) -> String {
        guard device.online else { return "Offline" }
        if let on = device.isOn {
            guard on else { return "Off" }
            if let level = device.number("brightness") { return "On · \(Int(level))%" }
            return "On"
        }
        if let celsius = device.number("temperature") {
            return Measurement(value: celsius, unit: UnitTemperature.celsius).formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))
        }
        if let humidity = device.number("humidity") { return "\(Int(humidity))% humidity" }
        return device.productName ?? "Ready"
    }
}
