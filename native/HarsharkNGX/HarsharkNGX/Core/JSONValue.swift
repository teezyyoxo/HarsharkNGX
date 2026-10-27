import Foundation

/// Retains exporter-specific fields without coupling the core to Foundation's Any dictionaries.
nonisolated public enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case deferredString(HARTextReference)
    case number(Decimal)
    case bool(Bool)
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Decimal.self) {
            self = .number(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .deferredString(let reference): try container.encode(reference.text())
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var object: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var array: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var string: String? {
        switch self {
        case .string(let value): return value
        case .deferredString(let reference): return try? reference.text()
        default: return nil
        }
    }

    public var number: Double? {
        guard case .number(let value) = self else { return nil }
        return NSDecimalNumber(decimal: value).doubleValue
    }
    /// Conservative budget check before formatting/serializing potentially large lazy bodies.
    public func fitsJSONBudget(_ limit: Int) -> Bool {
        var remaining = max(0, limit)
        return consumeBudget(&remaining)
    }

    private func consumeBudget(_ remaining: inout Int) -> Bool {
        switch self {
        case .deferredString(let reference): remaining -= reference.byteCount
        case .string(let text): remaining -= text.utf8.count * 6 + 2
        case .number: remaining -= 128
        case .bool, .null: remaining -= 5
        case .array(let values):
            remaining -= values.count + 2
            for value in values {
                guard remaining >= 0, value.consumeBudget(&remaining) else { return false }
            }
        case .object(let values):
            remaining -= values.count * 2 + 2
            for (key, value) in values {
                remaining -= key.utf8.count * 6 + 2
                guard remaining >= 0, value.consumeBudget(&remaining) else { return false }
            }
        }
        return remaining >= 0
    }

}
