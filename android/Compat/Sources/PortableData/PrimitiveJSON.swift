import Foundation

/// A value `Snapshot` writes and reads as JSON directly: the types nearly every stored
/// property has. The output is what `JSONDecoder` reads back to the same value, and each
/// reader also accepts what `JSONEncoder` wrote, so rows from either path mix freely.
protocol PrimitiveJSON {
    /// `nil` for a value JSON cannot hold (a non-finite number).
    var json: Data? { get }
    /// `nil` when `raw` is not this type's JSON, and the caller falls back to `JSONDecoder`.
    init?(json raw: Data)
}

extension String: PrimitiveJSON {
    var json: Data? {
        var out = Data()
        out.reserveCapacity(utf8.count + 2)
        out.append(UInt8(ascii: "\""))
        for byte in utf8 {
            switch byte {
            case UInt8(ascii: "\""): out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "\"")])
            case UInt8(ascii: "\\"): out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "\\")])
            case 0x0A: out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "n")])
            case 0x0D: out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "r")])
            case 0x09: out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "t")])
            case 0x00 ..< 0x20: out.append(contentsOf: Array(String(format: "\\u%04x", byte).utf8))
            default: out.append(byte)
            }
        }
        out.append(UInt8(ascii: "\""))
        return out
    }

    /// A string without escapes is its bytes between the quotes; one with them goes to `JSONDecoder`.
    init?(json raw: Data) {
        guard raw.count >= 2, raw.first == UInt8(ascii: "\""), raw.last == UInt8(ascii: "\""),
              !raw.contains(UInt8(ascii: "\\"))
        else { return nil }
        self.init(decoding: raw.dropFirst().dropLast(), as: UTF8.self)
    }
}

extension Double: PrimitiveJSON {
    /// Swift's shortest representation that reads back to the same bits.
    var json: Data? {
        isFinite ? Data(description.utf8) : nil
    }

    init?(json raw: Data) {
        guard let value = Double(String(decoding: raw, as: UTF8.self)), value.isFinite else { return nil }
        self = value
    }
}

extension Int: PrimitiveJSON {
    var json: Data? {
        Data(String(self).utf8)
    }

    init?(json raw: Data) {
        guard let value = Int(String(decoding: raw, as: UTF8.self)) else { return nil }
        self = value
    }
}

extension Bool: PrimitiveJSON {
    var json: Data? {
        Data((self ? "true" : "false").utf8)
    }

    init?(json raw: Data) {
        if raw.elementsEqual("true".utf8) {
            self = true
        } else if raw.elementsEqual("false".utf8) {
            self = false
        } else {
            return nil
        }
    }
}

/// Seconds since the reference date, as `JSONEncoder`'s default date strategy stores it.
extension Date: PrimitiveJSON {
    var json: Data? {
        timeIntervalSinceReferenceDate.json
    }

    init?(json raw: Data) {
        guard let seconds = Double(json: raw) else { return nil }
        self.init(timeIntervalSinceReferenceDate: seconds)
    }
}

extension UUID: PrimitiveJSON {
    var json: Data? {
        uuidString.json
    }

    init?(json raw: Data) {
        guard let string = String(json: raw), let value = UUID(uuidString: string) else { return nil }
        self = value
    }
}

/// Base64, as `JSONEncoder`'s default data strategy stores it.
extension Data: PrimitiveJSON {
    var json: Data? {
        base64EncodedString().json
    }

    init?(json raw: Data) {
        guard let string = String(json: raw), let value = Data(base64Encoded: string) else { return nil }
        self = value
    }
}

extension Optional: PrimitiveJSON where Wrapped: PrimitiveJSON {
    var json: Data? {
        switch self {
        case let .some(value): value.json
        case .none: Data("null".utf8)
        }
    }

    init?(json raw: Data) {
        if RowCodec.isNull(raw) {
            self = .none
        } else if let value = Wrapped(json: raw) {
            self = .some(value)
        } else {
            return nil
        }
    }
}
