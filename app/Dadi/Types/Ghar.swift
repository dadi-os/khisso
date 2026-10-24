import Foundation

/// Any JSON value, for open-ended payloads: Ghar's device state and capability config, and Hath's log rows.
enum JSONValue: Decodable, Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    var number: Double? { if case .number(let v) = self { v } else { nil } }
    var string: String? { if case .string(let v) = self { v } else { nil } }
    var array: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
    var object: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }
}

/// A room from GET /rooms.
struct GharRoom: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
}

/// A device from GET /devices: what it is, where it is, what it can do, and
/// its live state.
struct GharDevice: Decodable, Sendable, Hashable, Identifiable {
    /// One capability and its config (color modes, ranges, choices).
    struct Capability: Decodable, Sendable, Hashable {
        let capability: String
        let config: [String: JSONValue]
    }

    /// One live attribute.
    struct Attribute: Decodable, Sendable, Hashable {
        let value: JSONValue
    }

    /// A Ghar tag on the device; the app calls tags groups.
    struct Tag: Decodable, Sendable, Hashable {
        let id: String
        let name: String
    }

    let id: String
    let name: String
    /// What it is, from its Matter device type: light, plug, sensor kinds, …
    let kind: String
    let productName: String?
    let room: GharRoom
    let tags: [Tag]
    let capabilities: [Capability]
    let online: Bool
    /// Live state; the app changes it ahead of Ghar's answer and puts it back
    /// if the command fails.
    var state: [String: Attribute]

    func has(_ capability: String) -> Bool { capabilities.contains { $0.capability == capability } }
    func config(_ capability: String) -> [String: JSONValue]? { capabilities.first { $0.capability == capability }?.config }
    func number(_ key: String) -> Double? { state[key]?.value.number }

    /// Whether it is on, for devices that switch.
    var isOn: Bool? { state["on"]?.value.bool }

    /// The color modes its color capability supports: `hue_sat`, `color_temp`.
    var colorModes: [String] { config("color")?["modes"]?.array?.compactMap(\.string) ?? [] }

    /// The names of its groups.
    var groups: [String] { tags.map(\.name) }

    /// This device with `key` set to `value`.
    func with(_ key: String, _ value: JSONValue) -> GharDevice {
        var next = self
        next.state[key] = Attribute(value: value)
        return next
    }
}

/// Body of PATCH /devices/:id: only the fields given change.
struct GharDevicePatch: Encodable, Sendable {
    var name: String?
    var room: String?
    /// The device's whole tag list, replacing what it had.
    var tags: [String]?
}

/// Body of POST /devices/:id/command.
struct GharCommand: Encodable, Sendable {
    let capability: String
    let command: String
    let params: [String: Int]?

    static let toggle = GharCommand(capability: "on_off", command: "toggle", params: nil)
    static let on = GharCommand(capability: "on_off", command: "on", params: nil)
    static let off = GharCommand(capability: "on_off", command: "off", params: nil)

    /// Brightness 0–100; a light or plug also switches on.
    static func level(_ level: Int) -> GharCommand { GharCommand(capability: "level", command: "move_to", params: ["level": level]) }

    /// White temperature in mireds (153 cool to 500 warm).
    static func temperature(mireds: Int) -> GharCommand { GharCommand(capability: "color", command: "temperature", params: ["mireds": mireds]) }

    /// Color on Matter's 0–254 hue and saturation scales.
    static func hue(_ hue: Int, saturation: Int) -> GharCommand { GharCommand(capability: "color", command: "hue_saturation", params: ["hue": hue, "saturation": saturation]) }
}
