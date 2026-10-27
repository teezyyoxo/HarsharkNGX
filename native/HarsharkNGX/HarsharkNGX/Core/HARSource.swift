import Foundation

/// Immutable private snapshot: mapped body ranges remain valid even if the original file changes.
nonisolated public final class HARSource: @unchecked Sendable {
    public let id = UUID()
    public let data: Data
    private let snapshotURL: URL?

    init(data: Data) {
        self.data = data
        snapshotURL = nil
    }

    init(fileURL: URL) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HarsharkNGX", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let snapshot = directory.appendingPathComponent(UUID().uuidString + ".har")
        do {
            try FileManager.default.copyItem(at: fileURL, to: snapshot)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshot.path)
            data = try Data(contentsOf: snapshot, options: [.alwaysMapped])
            snapshotURL = snapshot
        } catch {
            try? FileManager.default.removeItem(at: snapshot)
            throw error
        }
    }

    deinit {
        if let snapshotURL { try? FileManager.default.removeItem(at: snapshotURL) }
    }
}

nonisolated public struct HARTextReference: Sendable, Equatable {
    public let source: HARSource
    public let range: Range<Int>
    public var byteCount: Int { range.count }

    public func text() throws -> String {
        try Task.checkCancellation()
        return try JSONDecoder().decode(String.self, from: source.data.subdata(in: range))
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source.id == rhs.source.id && lhs.range == rhs.range
    }
}

/// Validates JSON while retaining captured text as source ranges rather than decoded strings.
/// This bounds body allocations during import; metadata memory still scales with entry count.
nonisolated struct HARJSONScanner {
    let source: HARSource

    func parse() throws -> JSONValue {
        try source.data.withUnsafeBytes { buffer in
            var reader = Reader(bytes: buffer.bindMemory(to: UInt8.self), source: source)
            let value = try reader.value(depth: 0)
            reader.whitespace()
            guard reader.position == buffer.count else { throw HARImportError.invalidJSON }
            return value
        }
    }

    private struct Reader {
        let bytes: UnsafeBufferPointer<UInt8>
        let source: HARSource
        var position = 0

        mutating func whitespace() {
            while position < bytes.count && [UInt8(9), 10, 13, 32].contains(bytes[position]) { position += 1 }
        }

        mutating func take(_ byte: UInt8) -> Bool {
            whitespace()
            guard position < bytes.count, bytes[position] == byte else { return false }
            position += 1
            return true
        }

        mutating func value(depth: Int, deferString: Bool = false) throws -> JSONValue {
            try Task.checkCancellation()
            guard depth < 256 else { throw HARImportError.invalidJSON }
            whitespace()
            guard position < bytes.count else { throw HARImportError.invalidJSON }
            switch bytes[position] {
            case 123:
                position += 1
                var object: [String: JSONValue] = [:]
                if take(125) { return .object(object) }
                repeat {
                    whitespace()
                    let keyRange = try stringRange()
                    guard keyRange.count <= 1_048_576 else { throw HARImportError.invalidJSON }
                    let key = try JSONDecoder().decode(String.self, from: source.data.subdata(in: keyRange))
                    guard take(58) else { throw HARImportError.invalidJSON }
                    object[key] = try value(depth: depth + 1, deferString: key == "text")
                    if take(125) { return .object(object) }
                    guard take(44) else { throw HARImportError.invalidJSON }
                } while true
            case 91:
                position += 1
                var array: [JSONValue] = []
                if take(93) { return .array(array) }
                repeat {
                    array.append(try value(depth: depth + 1))
                    if take(93) { return .array(array) }
                    guard take(44) else { throw HARImportError.invalidJSON }
                } while true
            case 34:
                let range = try stringRange()
                if deferString { return .deferredString(HARTextReference(source: source, range: range)) }
                guard range.count <= 1_048_576 else {
                    throw HARImportError.invalidStructure(path: "metadata", expected: "strings no larger than 1 MiB")
                }
                return .string(try JSONDecoder().decode(String.self, from: source.data.subdata(in: range)))
            case 116: try literal("true"); return .bool(true)
            case 102: try literal("false"); return .bool(false)
            case 110: try literal("null"); return .null
            default:
                let start = position
                while position < bytes.count && ![UInt8(9), 10, 13, 32, 44, 93, 125].contains(bytes[position]) {
                    position += 1
                    guard position - start <= 128 else { throw HARImportError.invalidJSON }
                }
                guard position > start else { throw HARImportError.invalidJSON }
                let number = try JSONDecoder().decode(Decimal.self, from: source.data.subdata(in: start..<position))
                return .number(number)
            }
        }

        mutating func literal(_ expected: String) throws {
            for byte in expected.utf8 {
                guard position < bytes.count, bytes[position] == byte else { throw HARImportError.invalidJSON }
                position += 1
            }
        }

        mutating func stringRange() throws -> Range<Int> {
            let start = position
            guard position < bytes.count, bytes[position] == 34 else { throw HARImportError.invalidJSON }
            position += 1
            while position < bytes.count {
                if position & 0xFFFF == 0 { try Task.checkCancellation() }
                let byte = bytes[position]
                position += 1
                if byte == 34 { return start..<position }
                if byte == 92 {
                    guard position < bytes.count else { throw HARImportError.invalidJSON }
                    let escaped = bytes[position]
                    position += 1
                    if escaped == 117 {
                        let scalar = try hexQuad()
                        if (0xD800...0xDBFF).contains(scalar) {
                            guard position + 2 <= bytes.count, bytes[position] == 92, bytes[position + 1] == 117 else {
                                throw HARImportError.invalidJSON
                            }
                            position += 2
                            guard (0xDC00...0xDFFF).contains(try hexQuad()) else { throw HARImportError.invalidJSON }
                        } else if (0xDC00...0xDFFF).contains(scalar) { throw HARImportError.invalidJSON }
                    } else if ![UInt8(34), 92, 47, 98, 102, 110, 114, 116].contains(escaped) {
                        throw HARImportError.invalidJSON
                    }
                } else if byte < 32 {
                    throw HARImportError.invalidJSON
                } else if byte >= 128 {
                    // Validate UTF-8 without constructing a body-sized String.
                    let count: Int
                    var scalar: UInt32
                    if byte >= 0xC2 && byte <= 0xDF { count = 1; scalar = UInt32(byte & 0x1F) }
                    else if byte >= 0xE0 && byte <= 0xEF { count = 2; scalar = UInt32(byte & 0x0F) }
                    else if byte >= 0xF0 && byte <= 0xF4 { count = 3; scalar = UInt32(byte & 0x07) }
                    else { throw HARImportError.invalidJSON }
                    guard position + count <= bytes.count else { throw HARImportError.invalidJSON }
                    for _ in 0..<count {
                        let continuation = bytes[position]
                        guard continuation & 0xC0 == 0x80 else { throw HARImportError.invalidJSON }
                        scalar = (scalar << 6) | UInt32(continuation & 0x3F)
                        position += 1
                    }
                    let minimum: UInt32 = count == 1 ? 0x80 : (count == 2 ? 0x800 : 0x10000)
                    guard scalar >= minimum, scalar <= 0x10FFFF, !(0xD800...0xDFFF).contains(scalar) else {
                        throw HARImportError.invalidJSON
                    }
                }
            }
            throw HARImportError.invalidJSON
        }

        mutating func hexQuad() throws -> UInt32 {
            guard position + 4 <= bytes.count else { throw HARImportError.invalidJSON }
            var value: UInt32 = 0
            for _ in 0..<4 {
                let byte = bytes[position]
                let digit: UInt32
                switch byte {
                case 48...57: digit = UInt32(byte - 48)
                case 65...70: digit = UInt32(byte - 55)
                case 97...102: digit = UInt32(byte - 87)
                default: throw HARImportError.invalidJSON
                }
                value = value * 16 + digit
                position += 1
            }
            return value
        }
    }
}
