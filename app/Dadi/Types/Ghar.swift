import Foundation

/// Any JSON value, for Ghar's open-ended device state and capability config.
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

    let id: String
    let name: String
    /// What it is, from its Matter device type: light, plug, sensor kinds, …
    let kind: String
    let productName: String?
    let room: GharRoom
    let capabilities: [Capability]
    let online: Bool
    let state: [String: Attribute]

    func has(_ capability: String) -> Bool { capabilities.contains { $0.capability == capability } }
    func config(_ capability: String) -> [String: JSONValue]? { capabilities.first { $0.capability == capability }?.config }
    func number(_ key: String) -> Double? { state[key]?.value.number }

    /// Whether it is on, for devices that switch.
    var isOn: Bool? { state["on"]?.value.bool }
}

/// Body of POST /devices/:id/command.
struct GharCommand: Encodable, Sendable {
    let capability: String
    let command: String
    let params: [String: Int]?

    static let toggle = GharCommand(capability: "on_off", command: "toggle", params: nil)

    /// Brightness 1–100.
    static func level(_ level: Int) -> GharCommand { GharCommand(capability: "level", command: "move_to", params: ["level": level]) }

    /// White temperature in mireds (153 cool to 500 warm).
    static func temperature(mireds: Int) -> GharCommand { GharCommand(capability: "color", command: "temperature", params: ["mireds": mireds]) }

    /// Color on Matter's 0–254 hue and saturation scales.
    static func hue(_ hue: Int, saturation: Int) -> GharCommand { GharCommand(capability: "color", command: "hue_saturation", params: ["hue": hue, "saturation": saturation]) }
}
