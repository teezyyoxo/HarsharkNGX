import Foundation

/// A deliberately small allowlist avoids copying credentials hidden in exporter-specific fields.
/// This produces a summary HAR; it is not a lossless sanitized copy of the original.
nonisolated public enum HARSanitizer {
    public static func summaryData(_ archive: HARArchive) throws -> Data {
        let entries = try archive.entries.map { entry -> JSONValue in
            try Task.checkCancellation()
            var origin = URLComponents()
            if let url = URLComponents(string: entry.url),
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                origin.scheme = url.scheme
                origin.host = url.host
                origin.port = url.port
            }
            var request: [String: JSONValue] = [
                "method": .string(entry.method), "url": .string(origin.string ?? ""),
                "headers": .array([]), "cookies": .array([]), "queryString": .array([])
            ]
            if let version = entry.request["httpVersion"]?.string { request["httpVersion"] = .string(version) }
            var content: [String: JSONValue] = [:]
            for key in ["size", "mimeType"] {
                if let value = entry.response["content"]?.object?[key],
                   value.number != nil || (key == "mimeType" && value.string != nil) { content[key] = value }
            }
            var response: [String: JSONValue] = [
                "headers": .array([]), "cookies": .array([]), "content": .object(content)
            ]
            if let status = entry.status { response["status"] = .number(Decimal(status)) }
            if let version = entry.response["httpVersion"]?.string { response["httpVersion"] = .string(version) }
            var result: [String: JSONValue] = ["request": .object(request), "response": .object(response)]
            if let time = entry.durationMilliseconds { result["time"] = .number(Decimal(time)) }
            var timings: [String: JSONValue] = [:]
            for key in ["blocked", "dns", "connect", "ssl", "send", "wait", "receive"] {
                if let value = entry.raw["timings"]?.object?[key], value.number != nil { timings[key] = value }
            }
            result["timings"] = .object(timings)
            return .object(result)
        }
        let value = JSONValue.object(["log": .object([
            "version": .string("1.2"),
            "creator": .object(["name": .string("HarsharkNGX redacted summary"), "version": .string("1.0.0")]),
            "entries": .array(entries)
        ])])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
}
