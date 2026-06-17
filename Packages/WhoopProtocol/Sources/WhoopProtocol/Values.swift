import Foundation

/// Mirrors Python's heterogeneous parsed dict so values round-trip through JSON
/// byte-identically to the golden output. Encodes/decodes as a BARE JSON scalar/array
/// (not a tagged union), so golden.json's `parsed` values decode directly.
public enum ParsedValue: Codable, Equatable, Sendable {
    case int(Int)
    case double(Double)
    case string(String)
    case intArray([Int])
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            // Bool must be tried before Int: JSON true/false would otherwise mis-decode.
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([Int].self) {
            self = .intArray(a)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "Unsupported ParsedValue JSON")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .intArray(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

public extension ParsedValue {
    var intValue: Int? { if case .int(let v) = self { return v }; return nil }
    var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }
    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    var intArrayValue: [Int]? { if case .intArray(let v) = self { return v }; return nil }
}
