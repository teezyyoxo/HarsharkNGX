import Foundation

nonisolated public struct HAREntryID: Hashable, Sendable {
    public let sessionID: UUID
    public let ordinal: Int
}

nonisolated public struct HAREntry: Identifiable, Sendable {
    public let id: HAREntryID
    public let raw: [String: JSONValue]

    public var request: [String: JSONValue] { raw["request"]?.object ?? [:] }
    public var response: [String: JSONValue] { raw["response"]?.object ?? [:] }
    public var url: String { request["url"]?.string ?? "" }
    public var method: String { request["method"]?.string ?? "" }
    public var httpVersion: String { response["httpVersion"]?.string ?? request["httpVersion"]?.string ?? "" }
    public var status: Int? {
        guard let number = response["status"]?.number else { return nil }
        return Int(exactly: number)
    }
    public var startedDateTime: String? { raw["startedDateTime"]?.string }
    public var durationMilliseconds: Double? {
        guard let value = raw["time"]?.number, value.isFinite, value >= 0 else { return nil }
        return value
    }
    public var requestBody: HARBody { HARBody(blob: request["postData"]) }
    public var responseBody: HARBody { HARBody(blob: response["content"]) }
}

nonisolated public struct HARArchive: Sendable {
    public let sessionID: UUID
    /// Original bytes preserve exact source content, including unknown fields and number spelling.
    public let source: Data
    public let entries: [HAREntry]
    let backing: HARSource?
}

nonisolated public enum HARImportError: Error, LocalizedError, Sendable, Equatable {
    case inputTooLarge(limit: Int)
    case invalidJSON
    case invalidStructure(path: String, expected: String)

    public var errorDescription: String? {
        switch self {
        case .inputTooLarge(let limit):
            return "This importer accepts up to \(limit / 1_048_576) MiB. Streaming import is not available yet."
        case .invalidJSON:
            return "The file does not contain valid, supported JSON."
        case .invalidStructure(let path, let expected):
            return "Invalid HAR at \(path): expected \(expected)."
        }
    }
}

/// Bounded in-memory parsing for fixtures, plus file-backed indexing for desktop/MCP imports.
nonisolated public struct HARParser: Sendable {
    public static let maximumInputBytes = 32 * 1_048_576

    public init() {}

    public func parse(_ data: Data, sessionID: UUID = UUID()) throws -> HARArchive {
        try Task.checkCancellation()
        guard data.count <= Self.maximumInputBytes else {
            throw HARImportError.inputTooLarge(limit: Self.maximumInputBytes)
        }
        let root: JSONValue
        do {
            root = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw HARImportError.invalidJSON
        }
        return try archive(root: root, data: data, sessionID: sessionID, backing: nil)
    }

    private func archive(root: JSONValue, data: Data, sessionID: UUID, backing: HARSource?) throws -> HARArchive {
        try Task.checkCancellation()
        guard let object = root.object else {
            throw HARImportError.invalidStructure(path: "$", expected: "an object")
        }
        guard let log = object["log"]?.object else {
            throw HARImportError.invalidStructure(path: "log", expected: "an object")
        }
        guard let rawEntries = log["entries"]?.array else {
            throw HARImportError.invalidStructure(path: "log.entries", expected: "an array")
        }
        var entries: [HAREntry] = []
        entries.reserveCapacity(rawEntries.count)
        for (ordinal, value) in rawEntries.enumerated() {
            try Task.checkCancellation()
            let path = "log.entries[\(ordinal)]"
            guard let entry = value.object else {
                throw HARImportError.invalidStructure(path: path, expected: "an object")
            }
            for key in ["request", "response"] {
                guard entry[key]?.object != nil else {
                    throw HARImportError.invalidStructure(path: "\(path).\(key)", expected: "an object")
                }
            }
            entries.append(HAREntry(id: HAREntryID(sessionID: sessionID, ordinal: ordinal), raw: entry))
        }
        return HARArchive(sessionID: sessionID, source: data, entries: entries, backing: backing)
    }

    /// File imports use a private mapped snapshot and lazy body ranges; no 32 MiB file limit.
    public func read(from url: URL, sessionID: UUID = UUID()) throws -> HARArchive {
        try Task.checkCancellation()
        let backing = try HARSource(fileURL: url)
        let root: JSONValue
        do {
            root = try HARJSONScanner(source: backing).parse()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HARImportError {
            throw error
        } catch {
            throw HARImportError.invalidJSON
        }
        return try archive(root: root, data: backing.data, sessionID: sessionID, backing: backing)
    }
}
