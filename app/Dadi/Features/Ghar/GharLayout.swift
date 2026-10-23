import SwiftUI

/// A light's color as red, green and blue from 0 to 1.
struct LightColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }

    /// The white of a light at `kelvin`: Tanner Helland's fit of the
    /// black-body curve, leaning toward the warmth slider's cool blue above
    /// 4500 K so a daylight bulb still reads as lit on bone.
    static func white(kelvin: Double) -> LightColor {
        let body = blackBody(kelvin: kelvin)
        guard kelvin > 4500 else { return body }
        return body.mixed(with: LightColor(red: 0.788, green: 0.855, blue: 1), by: min(0.8, (kelvin - 4500) / 2000 * 0.8))
    }

    private static func blackBody(kelvin: Double) -> LightColor {
        let t = kelvin / 100
        let red = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let green = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let blue = t >= 66 ? 255 : t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307
        func unit(_ v: Double) -> Double { min(255, max(0, v)) / 255 }
        return LightColor(red: unit(red), green: unit(green), blue: unit(blue))
    }

    /// A color at full value from Matter's 0–254 hue and saturation.
    static func hue(_ hue: Double, saturation: Double) -> LightColor {
        let h = (hue / 254).truncatingRemainder(dividingBy: 1) * 6
        let s = min(1, max(0, saturation / 254))
        let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        let (r, g, b): (Double, Double, Double) = switch Int(h) {
        case 0: (1, x, 0)
        case 1: (x, 1, 0)
        case 2: (0, 1, x)
        case 3: (0, x, 1)
        case 4: (x, 0, 1)
        default: (1, 0, x)
        }
        return LightColor(red: 1 - s * (1 - r), green: 1 - s * (1 - g), blue: 1 - s * (1 - b))
    }

    /// The even mix of `colors`, or nil when there are none.
    static func blend(_ colors: [LightColor]) -> LightColor? {
        guard !colors.isEmpty else { return nil }
        let n = Double(colors.count)
        return LightColor(red: colors.map(\.red).reduce(0, +) / n, green: colors.map(\.green).reduce(0, +) / n, blue: colors.map(\.blue).reduce(0, +) / n)
    }

    /// This color moved `amount` of the way to `other`.
    func mixed(with other: LightColor, by amount: Double) -> LightColor {
        LightColor(red: red + (other.red - red) * amount, green: green + (other.green - green) * amount, blue: blue + (other.blue - blue) * amount)
    }

    static let black = LightColor(red: 0, green: 0, blue: 0)
    static let white = LightColor(red: 1, green: 1, blue: 1)
    /// dadi's sage, for devices that are on but give no light.
    static let sage = LightColor(red: 0.561, green: 0.639, blue: 0.510)
}

/// A room on the Ghar page and its devices, by name.
struct GharSection: Identifiable, Hashable {
    let room: GharRoom
    let devices: [GharDevice]

    var id: String { room.id }
    /// False for Ghar's `unassigned` room: devices not in a room.
    var placed: Bool { room.name != GharLayout.unassigned }
}

/// A Ghar tag and the devices that carry it.
struct GharGroup: Identifiable, Hashable {
    let name: String
    let devices: [GharDevice]

    var id: String { name }
}

/// How many of a set of devices are on, their brightness and their light.
struct GharSummary: Equatable {
    /// Devices that are on.
    let on: Int
    /// Devices that switch.
    let total: Int
    /// The mean brightness of the lit devices that dim, 0–100.
    let level: Int?
    /// The mix of the lit devices' colors.
    let color: LightColor?
}

/// A light's quick setting in the light sheet.
struct LightPreset: Identifiable {
    enum Setting {
        case white(mireds: Int)
        case hue(Int, saturation: Int)
    }

    let name: String
    let swatch: Color
    let setting: Setting

    var id: String { name }

    var command: GharCommand {
        switch setting {
        case .white(let mireds): .temperature(mireds: mireds)
        case .hue(let hue, let saturation): .hue(hue, saturation: saturation)
        }
    }

    /// Whether `device` shows this setting now.
    func matches(_ device: GharDevice) -> Bool {
        let mode = device.state["color_mode"]?.value.string
        switch setting {
        case .white(let mireds):
            guard mode == "color_temp", let current = device.number("color_temp") else { return false }
            return abs(current - Double(mireds)) <= 15
        case .hue(let hue, let saturation):
            guard mode == "hue_sat", let h = device.number("hue"), let s = device.number("saturation") else { return false }
            return abs(h - Double(hue)) <= 4 && abs(s - Double(saturation)) <= 12
        }
    }

    static let all = [
        LightPreset(name: "Candle", swatch: Color(red: 1, green: 0.706, blue: 0.420), setting: .white(mireds: 455)),
        LightPreset(name: "Warm white", swatch: Color(red: 1, green: 0.886, blue: 0.737), setting: .white(mireds: 370)),
        LightPreset(name: "Daylight", swatch: Color(red: 0.957, green: 0.969, blue: 1), setting: .white(mireds: 153)),
        LightPreset(name: "Peach", swatch: Color(red: 1, green: 0.667, blue: 0.510), setting: .hue(13, saturation: 124)),
        LightPreset(name: "Sage", swatch: Color(red: 0.663, green: 0.780, blue: 0.604), setting: .hue(71, saturation: 57)),
    ]
}

/// The Ghar page's arrangement: rooms and groups, what is on, and how a
/// device's light and state read.
enum GharLayout {
    /// Ghar's room for devices that are not in a room.
    static let unassigned = "unassigned"

    /// Evening: every light at this brightness in warm white.
    static let eveningLevel = 40
    /// 2700 K.
    static let eveningMireds = 370

    /// The coolest and warmest whites the warmth slider offers, in kelvin.
    static let warmthRange: ClosedRange<Double> = 2000...6500

    /// Every room by name, empty ones too, each with its devices by name, then
    /// the devices that are not in a room when there are any.
    static func sections(_ devices: [GharDevice], rooms: [GharRoom]) -> [GharSection] {
        let byRoom = Dictionary(grouping: devices, by: \.room.id)
        let sorted = rooms.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let placed = sorted.filter { $0.name != unassigned }.map { room in
            GharSection(room: room, devices: byName(byRoom[room.id] ?? []))
        }
        let loose = sorted.filter { $0.name == unassigned }.compactMap { room -> GharSection? in
            let inside = byRoom[room.id] ?? []
            return inside.isEmpty ? nil : GharSection(room: room, devices: byName(inside))
        }
        return placed + loose
    }

    /// Every tag on any device, by name, each with its devices by name.
    static func groups(_ devices: [GharDevice]) -> [GharGroup] {
        let names = Set(devices.flatMap(\.groups))
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
            GharGroup(name: name, devices: byName(devices.filter { $0.groups.contains(name) }))
        }
    }

    /// What is on among `devices`, how bright and in what light.
    static func summary(_ devices: [GharDevice]) -> GharSummary {
        let switching = devices.filter { $0.isOn != nil }
        let lit = switching.filter { $0.isOn == true }
        let levels = lit.compactMap { $0.has("level") ? $0.number("brightness") : nil }
        return GharSummary(
            on: lit.count,
            total: switching.count,
            level: levels.isEmpty ? nil : Int((levels.reduce(0, +) / Double(levels.count)).rounded()),
            color: LightColor.blend(lit.map(color))
        )
    }

    /// "All lights off", "2 of 3 lights on", or "No lights yet".
    static func headline(_ summary: GharSummary) -> String {
        guard summary.total > 0 else { return "No lights yet" }
        guard summary.on > 0 else { return summary.total == 1 ? "The light is off" : "All lights off" }
        return "\(summary.on) of \(summary.total) \(summary.total == 1 ? "light" : "lights") on"
    }

    /// "2 of 3 on", "All off", or "Nothing here yet" for a room or group.
    static func status(_ summary: GharSummary) -> String {
        guard summary.total > 0 else { return "Nothing here yet" }
        return summary.on == 0 ? "All off" : "\(summary.on) of \(summary.total) on"
    }

    /// Where the devices are: "3 lights in Ankur's room", "5 lights in 2
    /// rooms, 1 not in a room".
    static func whereabouts(_ sections: [GharSection]) -> String {
        let devices = sections.flatMap(\.devices)
        guard !devices.isEmpty else { return "Add a light from the box's Ghar page" }
        let noun = devices.allSatisfy { $0.kind == "light" } ? "light" : "device"
        func count(_ n: Int) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
        let rooms = sections.filter { $0.placed && !$0.devices.isEmpty }
        let loose = sections.filter { !$0.placed }.flatMap(\.devices).count
        let inRooms = rooms.reduce(0) { $0 + $1.devices.count }
        if rooms.isEmpty { return "\(count(loose)), none in a room" }
        let place = rooms.count == 1 ? "in \(rooms[0].room.name)" : "in \(rooms.count) rooms"
        return loose == 0 ? "\(count(inRooms)) \(place)" : "\(count(inRooms)) \(place), \(loose) not in a room"
    }

    /// A room's name as the page shows it.
    static func name(of room: GharRoom) -> String {
        room.name == unassigned ? "Not in a room" : room.name
    }

    /// The light `device` gives: its hue or white for a light, sage for
    /// anything else that is on.
    static func color(_ device: GharDevice) -> LightColor {
        guard device.kind == "light" else { return .sage }
        let mode = device.state["color_mode"]?.value.string
        if mode == "hue_sat", let hue = device.number("hue"), let saturation = device.number("saturation") {
            return .hue(hue, saturation: saturation)
        }
        if let mireds = device.number("color_temp"), mireds > 0 {
            return .white(kelvin: 1_000_000 / mireds)
        }
        return .white(kelvin: 2700)
    }

    /// The light's color in words: "Warm white", "Peach", "Blue"; nil for a
    /// light with no color or white control.
    static func colorName(_ device: GharDevice) -> String? {
        guard device.kind == "light", device.has("color") else { return nil }
        let mode = device.state["color_mode"]?.value.string
        if mode == "hue_sat", let hue = device.number("hue"), let saturation = device.number("saturation") {
            return hueName(hue, saturation: saturation)
        }
        if let mireds = device.number("color_temp"), mireds > 0 {
            return whiteName(kelvin: 1_000_000 / mireds)
        }
        return nil
    }

    /// The lit lights' colors in words, each once: "Warm white · peach".
    static func colorNames(_ devices: [GharDevice]) -> String? {
        var names: [String] = []
        for device in devices where device.isOn == true {
            if let name = colorName(device), !names.contains(name) { names.append(name) }
        }
        guard let first = names.first else { return nil }
        return ([first] + names.dropFirst().map { $0.lowercased() }).joined(separator: " · ")
    }

    /// The name of a white at `kelvin`.
    static func whiteName(kelvin: Double) -> String {
        switch kelvin {
        case ..<2450: "Candle"
        case ..<3300: "Warm white"
        case ..<4500: "Soft white"
        case ..<5600: "Neutral white"
        default: "Daylight"
        }
    }

    /// The name of a color on Matter's 0–254 hue and saturation scales.
    static func hueName(_ hue: Double, saturation: Double) -> String {
        let degrees = hue / 254 * 360
        let s = saturation / 254
        guard s >= 0.12 else { return "White" }
        switch degrees {
        case 12..<40: return s < 0.6 ? "Peach" : "Orange"
        case 40..<55: return "Amber"
        case 55..<70: return "Yellow"
        case 70..<150: return s < 0.45 ? "Sage" : "Green"
        case 150..<190: return "Teal"
        case 190..<215: return "Sky"
        case 215..<255: return "Blue"
        case 255..<290: return "Violet"
        case 290..<345: return "Pink"
        default: return s < 0.5 ? "Rose" : "Red"
        }
    }

    /// "80% · Warm white", "Off", "Offline", or a sensor's reading.
    static func status(_ device: GharDevice) -> String {
        guard device.online else { return "Offline" }
        if let on = device.isOn {
            guard on else { return "Off" }
            let level = device.has("level") ? device.number("brightness").map { "\(Int($0))%" } : nil
            let parts = [level, colorName(device)].compactMap { $0 }
            return parts.isEmpty ? "On" : parts.joined(separator: " · ")
        }
        if let celsius = device.number("temperature") {
            return Measurement(value: celsius, unit: UnitTemperature.celsius).formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))
        }
        if let humidity = device.number("humidity") { return "\(Int(humidity))% humidity" }
        return device.productName ?? "Ready"
    }

    /// A symbol for each kind of device.
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

    private static func byName(_ devices: [GharDevice]) -> [GharDevice] {
        devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
