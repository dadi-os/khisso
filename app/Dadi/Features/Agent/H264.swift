import Foundation

/// One frame as length-prefixed (AVCC) NAL units; `key` frames can start decoding.
struct H264Frame: Sendable, Equatable {
    let key: Bool
    let data: Data
}

/// What the splitter has completed, in stream order.
enum H264Event: Sendable, Equatable {
    /// The stream's SPS and PPS, when they first arrive or change.
    case config(sps: Data, pps: Data)
    case frame(H264Frame)
}

/// Splits Nas's raw H.264 stream (Annex B, an access unit delimiter before
/// every frame) into what a decoder takes: one configuration from the
/// stream's SPS and PPS, then one length-prefixed chunk per frame. A frame
/// completes when the next delimiter arrives.
struct H264Splitter {
    private static let idr: UInt8 = 5
    private static let sps: UInt8 = 7
    private static let pps: UInt8 = 8
    private static let delimiter: UInt8 = 9

    private var rest: [UInt8] = []
    private var sps: [UInt8]?
    private var pps: [UInt8]?
    private var pending: [[UInt8]] = []
    private var key = false

    /// Takes the next network chunk and returns what it completed.
    mutating func push(_ chunk: Data) -> [H264Event] {
        let (nalus, remainder) = Self.takeNalus(rest + chunk)
        rest = remainder
        var events: [H264Event] = []
        for nalu in nalus {
            let type = nalu[0] & 0x1f
            switch type {
            case Self.delimiter:
                if let frame = closeFrame() { events.append(.frame(frame)) }
            case Self.sps, Self.pps:
                if let config = setParameterSet(type, nalu) { events.append(config) }
            default:
                pending.append(nalu)
                key = key || type == Self.idr
            }
        }
        return events
    }

    /// The complete NAL units at the front of an Annex B buffer, start codes
    /// stripped, and the remainder from the start code of the unfinished one.
    static func takeNalus(_ buffer: [UInt8]) -> (nalus: [[UInt8]], rest: [UInt8]) {
        guard var start = startCode(in: buffer, from: 0) else {
            return ([], Array(buffer.suffix(2)))
        }
        var nalus: [[UInt8]] = []
        while let next = startCode(in: buffer, from: start + 3) {
            var end = next
            while end > start + 3 && buffer[end - 1] == 0 { end -= 1 }
            nalus.append(Array(buffer[(start + 3)..<end]))
            start = next
        }
        return (nalus, Array(buffer[start...]))
    }

    private static func startCode(in buffer: [UInt8], from: Int) -> Int? {
        var i = from
        while i + 2 < buffer.count {
            if buffer[i + 2] > 1 {
                i += 3
            } else if buffer[i] == 0 && buffer[i + 1] == 0 && buffer[i + 2] == 1 {
                return i
            } else {
                i += 1
            }
        }
        return nil
    }

    private mutating func closeFrame() -> H264Frame? {
        guard !pending.isEmpty else { return nil }
        var data = Data()
        for nalu in pending {
            withUnsafeBytes(of: UInt32(nalu.count).bigEndian) { data.append(contentsOf: $0) }
            data.append(contentsOf: nalu)
        }
        let frame = H264Frame(key: key, data: data)
        pending = []
        key = false
        return frame
    }

    private mutating func setParameterSet(_ type: UInt8, _ nalu: [UInt8]) -> H264Event? {
        if type == Self.sps {
            guard sps != nalu else { return nil }
            sps = nalu
        } else {
            guard pps != nalu else { return nil }
            pps = nalu
        }
        guard let sps, let pps else { return nil }
        return .config(sps: Data(sps), pps: Data(pps))
    }
}
