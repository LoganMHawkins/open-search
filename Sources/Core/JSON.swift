import Foundation

/// Loosely typed JSON. Context.dev responses are wide and mostly nullable, so views read fields
/// through forgiving accessors (`json.person.name.full.nonEmpty`) instead of a Codable model per endpoint.
@dynamicMemberLookup
enum JSON: Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    subscript(key: String) -> JSON {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    subscript(index: Int) -> JSON {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return .null
    }

    subscript(dynamicMember key: String) -> JSON { self[key] }

    var str: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// The string, trimmed, or nil when missing / blank.
    var nonEmpty: String? {
        guard let s = str?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// Any scalar rendered as text.
    var display: String? {
        switch self {
        case .string: return nonEmpty
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "Yes" : "No"
        default: return nil
        }
    }

    var num: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    var int: Int? {
        guard let n = num, n.isFinite, abs(n) < 9e15 else { return nil }
        return Int(n)
    }

    var flag: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var list: [JSON] {
        if case .array(let a) = self { return a }
        return []
    }

    var dict: [String: JSON] {
        if case .object(let o) = self { return o }
        return [:]
    }

    var strings: [String] { list.compactMap(\.nonEmpty) }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Null, empty string, empty array or empty object.
    var isBlank: Bool {
        switch self {
        case .null: return true
        case .string(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let a): return a.isEmpty
        case .object(let o): return o.isEmpty
        default: return false
        }
    }

    var isScalar: Bool {
        switch self {
        case .array, .object: return false
        default: return true
        }
    }

    /// Foundation representation, for building request bodies.
    var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map(\.any)
        case .object(let o): return o.mapValues(\.any)
        }
    }

    init(any value: Any) {
        switch value {
        case is NSNull: self = .null
        case let n as NSNumber:
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map { JSON(any: $0) })
        case let o as [String: Any]: self = .object(o.mapValues { JSON(any: $0) })
        default: self = .null
        }
    }

    var pretty: String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: any, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]),
            let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }
}

extension JSON: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSON].self) { self = .object(o) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

// MARK: - Request-building helpers

extension String {
    /// nil when the string is blank, so optional request fields can be dropped.
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Splits on commas, semicolons, spaces and newlines.
    var tokens: [String] {
        components(separatedBy: CharacterSet(charactersIn: ",; \n\t")).filter { !$0.isEmpty }
    }

    var asInt: Int? { Int(trimmingCharacters(in: .whitespaces)) }
}

extension Dictionary where Key == String, Value == Any {
    /// Sets the value only when it is non-nil.
    mutating func put(_ key: String, _ value: Any?) {
        if let value { self[key] = value }
    }

    /// Sets the value only when it is a non-empty collection.
    mutating func put<T: Collection>(_ key: String, nonEmpty value: T) {
        if !value.isEmpty { self[key] = value }
    }
}
