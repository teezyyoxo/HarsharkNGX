import Foundation

nonisolated public struct HARRow: Identifiable, Sendable, Equatable {
    public let id: Int
    public let started: String
    public let method: String
    public let status: Int
    public let httpVersion: String
    public let host: String
    public let path: String
    public let url: String
    public let mimeType: String
    public let duration: Double
    public let size: Double

    public init(entry: HAREntry) {
        id = entry.id.ordinal
        started = entry.startedDateTime ?? ""
        method = entry.method
        status = entry.status ?? 0
        httpVersion = entry.httpVersion
        url = entry.url
        let components = URLComponents(string: entry.url)
        host = components?.host ?? ""
        path = (components?.percentEncodedPath.isEmpty == false ? components?.percentEncodedPath : "/") ?? "/"
        mimeType = entry.response["content"]?.object?["mimeType"]?.string ?? ""
        duration = entry.durationMilliseconds ?? -1
        size = entry.response["content"]?.object?["size"]?.number ?? -1
    }

    public func value(for column: String) -> String {
        switch column {
        case "started": return started
        case "method": return method
        case "status": return status == 0 ? "—" : String(status)
        case "protocol": return httpVersion
        case "host": return host
        case "path": return path
        case "mime": return mimeType
        case "duration", "waterfall": return duration < 0 ? "—" : String(format: "%.2f ms", duration)
        case "size": return size < 0 ? "—" : ByteCountFormatter.string(fromByteCount: Int64(min(size, Double(Int64.max / 2))), countStyle: .file)
        default: return ""
        }
    }

    public func matches(_ query: String) -> Bool {
        [started, method, String(status), httpVersion, host, path, url, mimeType, value(for: "duration")]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

nonisolated public enum HARDetailTab: String, CaseIterable, Sendable, Identifiable {
    case body = "Body"
    case parameters = "Parameters"
    case cookies = "Cookies"
    case headers = "Headers"
    case saml = "SAML"
    case timings = "Timings"
    case raw = "Raw JSON"

    public var id: String { rawValue }
}

nonisolated public struct HARDetail: Sendable, Equatable {
    public let text: String
    public let notice: String
    public let syntax: String

    public init(text: String = "", notice: String = "", syntax: String = "plain") {
        self.text = text
        self.notice = notice
        self.syntax = syntax
    }
}

nonisolated public enum HARFormatter {
    public static func detail(entry: HAREntry, response: Bool, tab: HARDetailTab, pretty: Bool, maximumBodyBytes: Int = 8 * 1_048_576) -> HARDetail {
        let object = response ? entry.response : entry.request
        switch tab {
        case .body:
            return bodyDetail(response ? entry.responseBody : entry.requestBody, pretty: pretty, maximumBodyBytes: maximumBodyBytes)
        case .headers:
            return nonempty(pairs(object["headers"]), empty: "No headers were captured.", syntax: "headers")
        case .cookies:
            return nonempty(pairs(object["cookies"]), empty: "No cookies were captured.")
        case .parameters:
            if response {
                return nonempty(parameters(object["content"]?.object?["params"]), empty: "No response parameters were captured.")
            }
            var query = pairs(object["queryString"])
            if query.isEmpty {
                query = URLComponents(string: entry.url)?.queryItems?.map { "\($0.name): \($0.value ?? "")" }.joined(separator: "\n") ?? ""
            }
            let post = parameters(object["postData"]?.object?["params"])
            return nonempty([query.isEmpty ? "" : "Query parameters\n\(query)", post.isEmpty ? "" : "Body parameters\n\(post)"]
                .filter { !$0.isEmpty }.joined(separator: "\n\n"), empty: "No parameters were captured.")
        case .saml:
            return saml(entry)
        case .timings:
            let timings = entry.raw["timings"]?.object ?? [:]
            let names = ["blocked", "dns", "connect", "ssl", "send", "wait", "receive"]
            let text = names.map { name in
                let value = timings[name]?.number ?? -1
                return "\(name.capitalized): \(value < 0 ? "Not captured" : String(format: "%.2f ms", value))"
            }.joined(separator: "\n")
            return HARDetail(text: text, notice: "SSL is part of connect time; do not add it twice.")
        case .raw:
            guard JSONValue.object(object).fitsJSONBudget(2 * 1_048_576) else {
                return HARDetail(notice: "Raw JSON exceeds the preview budget. Use Export Body to save the complete payload.")
            }
            return HARDetail(text: json(.object(object), pretty: pretty), syntax: "json")
        }
    }

    public static func bodyDetail(_ body: HARBody, pretty: Bool, maximumBodyBytes: Int = 8 * 1_048_576) -> HARDetail {
        switch body.presentation(maximumEncodedBytes: maximumBodyBytes) {
        case .text(let text):
            if pretty, text.utf8.count < 1_048_576,
               let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) {
                return HARDetail(text: json(value, pretty: true), syntax: "json")
            }
            return HARDetail(text: text, notice: text.utf8.count >= 1_048_576 ? "Large body: showing original text without formatting." : "")
        case .empty: return HARDetail(notice: "Captured body is empty.")
        case .missing: return HARDetail(notice: "Body text was not included in this HAR capture. Check Parameters for form fields.")
        case .unavailable(let reason), .unsupported(let reason), .malformed(let reason):
            return HARDetail(notice: reason)
        case .binary(let count, let mime):
            return HARDetail(notice: "Binary body · \(ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)) · \(mime ?? "unknown type"). Use Export Body to save the bytes.")
        }
    }

    public static func pairs(_ value: JSONValue?) -> String {
        (value?.array ?? []).compactMap { value -> String? in
            guard let object = value.object else { return nil }
            return "\(object["name"]?.string ?? ""): \(display(object["value"]))"
        }.joined(separator: "\n")
    }

    public static func parameters(_ value: JSONValue?) -> String {
        (value?.array ?? []).compactMap { value -> String? in
            guard let object = value.object else { return nil }
            var parts = [display(object["value"])]
            if let file = object["fileName"]?.string { parts.append("file: \(file)") }
            if let type = object["contentType"]?.string { parts.append(type) }
            return "\(object["name"]?.string ?? ""): \(parts.filter { !$0.isEmpty }.joined(separator: " · "))"
        }.joined(separator: "\n")
    }

    public static func json(_ value: JSONValue, pretty: Bool = true) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "Unable to serialize JSON." }
        return String(decoding: data, as: UTF8.self)
    }

    private static func display(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        return value.string ?? json(value, pretty: false)
    }

    private static func nonempty(_ text: String, empty: String, syntax: String = "plain") -> HARDetail {
        HARDetail(text: text, notice: text.isEmpty ? empty : "", syntax: syntax)
    }

    private static func saml(_ entry: HAREntry) -> HARDetail {
        let params = (entry.request["postData"]?.object?["params"]?.array ?? [])
            + (entry.request["queryString"]?.array ?? [])
        var candidate = params.first {
            ["samlrequest", "samlresponse"].contains($0.object?["name"]?.string?.lowercased() ?? "")
        }?.object?["value"]?.string
        if candidate == nil, case .text(let body) = entry.requestBody.presentation() {
            candidate = body
            if !body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
                candidate = URLComponents(string: "https://local.invalid/?\(body)")?.queryItems?
                    .first { ["samlrequest", "samlresponse"].contains($0.name.lowercased()) }?.value
            }
        }
        guard var text = candidate, !text.isEmpty else { return HARDetail(notice: "No SAML payload was found.") }
        guard text.utf8.count <= 1_048_576 else { return HARDetail(notice: "SAML payload exceeds the 1 MiB formatting limit.") }
        if let data = Data(base64Encoded: text), let decoded = String(data: data, encoding: .utf8) { text = decoded }
        guard text.contains("<") else { return HARDetail(text: text, notice: "SAML is encoded or compressed in an unsupported form; showing captured data.") }
        // Never resolve external entities in captured, untrusted XML.
        if let document = try? XMLDocument(xmlString: text, options: [.nodeLoadExternalEntitiesNever]) {
            return HARDetail(text: document.xmlString(options: [.nodePrettyPrint]))
        }
        return HARDetail(text: text, notice: "SAML XML could not be formatted; showing captured text.")
    }
}
