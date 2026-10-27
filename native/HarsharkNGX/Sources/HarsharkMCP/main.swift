import Foundation
import Darwin
import HarsharkCore

/// A standalone stdio process. No AppKit, GUI connection, listener port, or Python runtime.
final class MCPServer {
    private var archive: HARArchive?
    private var rows: [HARRow] = []
    private var currentPath: String?
    private var initialized = false
    private let sessionDirectory: URL
    private let accessControl: MCPAccessControl
    private var accessState: MCPAccessControl.State?

    init(sessionDirectory: URL) {
        self.sessionDirectory = sessionDirectory
        accessControl = MCPAccessControl(sessionDirectory: sessionDirectory)
    }

    func run() {
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            // A POSIX pipe read returns available bytes, rather than waiting to fill 4 KiB.
            let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                FileHandle.standardError.write(Data("MCP input read failed.\n".utf8))
                return
            }
            if count == 0 { break }
            pending.append(contentsOf: buffer.prefix(count))
            while let newline = pending.firstIndex(of: 10) {
                let line = pending.subdata(in: pending.startIndex..<newline)
                pending.removeSubrange(pending.startIndex...newline)
                guard line.count <= 1_048_576 else {
                    writeError(id: NSNull(), code: -32600, message: "MCP message exceeds 1 MiB.")
                    return
                }
                if !line.isEmpty { handle(line) }
            }
            if pending.count > 1_048_576 {
                writeError(id: NSNull(), code: -32600, message: "MCP message exceeds 1 MiB.")
                return
            }
        }
        if !pending.isEmpty { handle(pending) }
    }

    private func handle(_ data: Data) {
        guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            writeError(id: NSNull(), code: -32700, message: "Invalid JSON-RPC message.")
            return
        }
        guard let id = message["id"] else { return }
        guard message["jsonrpc"] as? String == "2.0", let method = message["method"] as? String else {
            writeError(id: id, code: -32600, message: "Expected JSON-RPC 2.0 request.")
            return
        }
        let params = message["params"] as? [String: Any] ?? [:]
        do {
            // Refresh for every request, including already-connected clients.
            // A revision also clears cached captures after an off/on cycle between requests.
            let access: MCPAccessControl.State
            do {
                access = try accessControl.read()
            } catch {
                clearCapture()
                throw MCPError.message("MCP access settings could not be read. Check HarsharkNGX before retrying.")
            }
            if access != accessState {
                clearCapture()
                accessState = access
            }
            let result: [String: Any]
            switch method {
            case "initialize":
                let requested = params["protocolVersion"] as? String ?? "2025-11-25"
                let supported = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
                initialized = true
                result = ["protocolVersion": supported.contains(requested) ? requested : "2025-11-25",
                          "capabilities": ["tools": ["listChanged": false], "resources": ["subscribe": false, "listChanged": false]],
                          "serverInfo": ["name": "harsharkngx", "version": "1.0.0"]]
            case "ping": result = [:]
            default:
                guard initialized else { throw MCPError.message("Call initialize before using the server.") }
                switch method {
                case "tools/list": result = ["tools": tools]
                case "tools/call":
                    do {
                        guard access.enabled else { throw MCPError.message("MCP is off. Enable MCP using the bottom-right button in HarsharkNGX.") }
                        let payload = try call(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:])
                        result = ["content": [["type": "text", "text": try json(payload)]]]
                    } catch {
                        result = ["isError": true, "content": [["type": "text", "text": error.localizedDescription]]]
                    }
                case "resources/list":
                    result = ["resources": [resource("summary", "Loaded HAR summary"), resource("entries", "Loaded HAR entries")]]
                case "resources/read":
                    guard access.enabled else { throw MCPError.message("MCP is off. Enable MCP using the bottom-right button in HarsharkNGX.") }
                    let uri = params["uri"] as? String ?? ""
                    let payload: [String: Any]
                    if uri == "harsharkngx://summary" { payload = try summary() }
                    else if uri == "harsharkngx://entries" { payload = try list(["limit": 200]) }
                    else { throw MCPError.message("Unknown resource: \(uri)") }
                    result = ["contents": [["uri": uri, "mimeType": "application/json", "text": try json(payload)]]]
                default:
                    writeError(id: id, code: -32601, message: "Unknown method: \(method)")
                    return
                }
            }
            write(["jsonrpc": "2.0", "id": id, "result": result])
        } catch {
            writeError(id: id, code: -32000, message: error.localizedDescription)
        }
    }

    private func clearCapture() {
        archive = nil
        rows = []
        currentPath = nil
    }

    private func call(_ name: String, _ args: [String: Any]) throws -> [String: Any] {
        switch name {
        case "load_har":
            guard let path = args["path"] as? String, !path.isEmpty else { throw MCPError.message("path is required.") }
            return try load(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        case "summarize_har": return try summary()
        case "list_entries", "search_entries": return try list(args)
        case "get_entry":
            let archive = try loaded()
            guard let index = args["index"] as? Int, archive.entries.indices.contains(index) else { throw MCPError.message("Entry index is out of range.") }
            let entry = archive.entries[index]
            var result = rowJSON(rows[index])
            result["request"] = details(entry, response: false)
            result["response"] = details(entry, response: true)
            if args["include_raw"] as? Bool == true {
                guard JSONValue.object(entry.raw).fitsJSONBudget(2_097_152) else {
                    throw MCPError.message("Raw entry exceeds the preview budget. Fetch body pages with get_body instead.")
                }
                let raw = HARFormatter.json(.object(entry.raw))
                guard raw.utf8.count <= 2_097_152 else { throw MCPError.message("Raw entry exceeds 2 MiB. Fetch body pages with get_body instead.") }
                result["raw"] = try JSONSerialization.jsonObject(with: Data(raw.utf8))
            }
            return result
        case "get_body":
            let archive = try loaded()
            guard let index = args["index"] as? Int, archive.entries.indices.contains(index) else { throw MCPError.message("Entry index is out of range.") }
            let response = args["side"] as? String != "request"
            let entry = archive.entries[index]
            let detail = HARFormatter.bodyDetail(response ? entry.responseBody : entry.requestBody, pretty: false)
            let offset = max(0, args["offset"] as? Int ?? 0)
            let limit = min(100_000, max(1, args["limit"] as? Int ?? 20_000))
            let page = String(detail.text.dropFirst(offset).prefix(limit))
            return ["text": page, "offset": offset, "chars": detail.text.count, "truncated": offset + page.count < detail.text.count, "notice": detail.notice]
        case "list_sessions":
            let urls = (try? FileManager.default.contentsOfDirectory(at: sessionDirectory, includingPropertiesForKeys: nil)) ?? []
            return ["directory": sessionDirectory.path, "sessions": urls.filter { $0.pathExtension == "har" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map {
                ["id": $0.deletingPathExtension().lastPathComponent, "name": $0.lastPathComponent]
            }]
        case "open_session":
            guard let id = args["id"] as? String, UUID(uuidString: id) != nil else { throw MCPError.message("A session UUID from list_sessions is required.") }
            return try load(sessionDirectory.appendingPathComponent(id).appendingPathExtension("har"))
        default: throw MCPError.message("Unknown tool: \(name)")
        }
    }

    private func load(_ url: URL) throws -> [String: Any] {
        let replacement = try HARParser().read(from: url)
        archive = replacement
        rows = replacement.entries.map(HARRow.init)
        currentPath = url.path
        return ["path": url.path, "entry_count": rows.count]
    }

    private func loaded() throws -> HARArchive {
        guard let archive else { throw MCPError.message("No HAR loaded. Call load_har, or list_sessions then open_session. The GUI does not need to be running.") }
        return archive
    }

    private func summary() throws -> [String: Any] {
        _ = try loaded()
        var statuses: [String: Int] = [:]
        var methods: [String: Int] = [:]
        var hosts: [String: Int] = [:]
        for row in rows {
            statuses[String(row.status), default: 0] += 1
            methods[row.method, default: 0] += 1
            hosts[row.host, default: 0] += 1
        }
        return ["path": currentPath ?? "", "entry_count": rows.count, "status_counts": statuses,
                "method_counts": methods, "top_hosts": hosts.sorted { $0.value > $1.value }.prefix(20).map { [$0.key, $0.value] as [Any] },
                "slowest_entries": rows.sorted { $0.duration > $1.duration }.prefix(10).map(rowJSON)]
    }

    private func list(_ args: [String: Any]) throws -> [String: Any] {
        let archive = try loaded()
        let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let offset = max(0, args["offset"] as? Int ?? 0)
        let limit = min(200, max(1, args["limit"] as? Int ?? 50))
        var total = 0
        var page: [[String: Any]] = []
        for row in rows {
            var matches = query.isEmpty || row.matches(query)
            if !matches {
                let entry = archive.entries[row.id]
                matches = [entry.requestBody, entry.responseBody].contains { body in
                    if case .text(let value) = body.presentation(maximumEncodedBytes: 8 * 1_048_576) {
                        return value.localizedCaseInsensitiveContains(query)
                    }
                    return false
                }
                if !matches {
                    matches = [entry.request["headers"], entry.response["headers"], entry.request["queryString"], entry.request["cookies"], entry.response["cookies"]]
                        .contains { HARFormatter.json($0 ?? .null, pretty: false).localizedCaseInsensitiveContains(query) }
                }
            }
            if matches {
                if total >= offset && page.count < limit { page.append(rowJSON(row)) }
                total += 1
            }
        }
        return ["path": currentPath ?? "", "total_matches": total, "offset": offset, "limit": limit, "entries": page]
    }

    private func details(_ entry: HAREntry, response: Bool) -> [String: Any] {
        let detail = HARFormatter.detail(entry: entry, response: response, tab: .body, pretty: false)
        let text = String(detail.text.prefix(20_000))
        return ["headers": HARFormatter.detail(entry: entry, response: response, tab: .headers, pretty: false).text,
                "parameters": HARFormatter.detail(entry: entry, response: response, tab: .parameters, pretty: false).text,
                "cookies": HARFormatter.detail(entry: entry, response: response, tab: .cookies, pretty: false).text,
                "body": ["text": text, "truncated": text.count < detail.text.count, "chars": detail.text.count, "notice": detail.notice]]
    }

    private func rowJSON(_ row: HARRow) -> [String: Any] {
        ["index": row.id, "started": row.started, "method": row.method, "status": String(row.status),
         "protocol": row.httpVersion, "host": row.host, "path": row.path, "full_url": row.url,
         "mime_type": row.mimeType, "time_ms": row.duration]
    }

    private func resource(_ name: String, _ title: String) -> [String: Any] {
        ["uri": "harsharkngx://\(name)", "name": title, "mimeType": "application/json"]
    }

    private func tool(_ name: String, _ description: String, _ properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
        ["name": name, "description": description, "inputSchema": ["type": "object", "properties": properties, "required": required]]
    }

    private var tools: [[String: Any]] {
        let index: [String: Any] = ["type": "integer", "minimum": 0]
        let limit: [String: Any] = ["type": "integer", "minimum": 1, "maximum": 200]
        return [
            tool("load_har", "Load a local HAR independently of the GUI.", ["path": ["type": "string"]], required: ["path"]),
            tool("summarize_har", "Summarize the loaded capture."),
            tool("list_entries", "List entries; body search is bounded to 8 MiB per body.", ["query": ["type": "string"], "offset": index, "limit": limit]),
            tool("search_entries", "Search captured metadata and bodies.", ["query": ["type": "string"], "limit": limit], required: ["query"]),
            tool("get_entry", "Inspect an entry with explicit body availability.", ["index": index, "include_raw": ["type": "boolean"]], required: ["index"]),
            tool("get_body", "Read a body preview page (bodies up to 8 MiB).", ["index": index, "side": ["type": "string", "enum": ["request", "response"]], "offset": index, "limit": ["type": "integer", "minimum": 1, "maximum": 100000]], required: ["index"]),
            tool("list_sessions", "List capture snapshots explicitly shared by the GUI."),
            tool("open_session", "Open a shared capture even after the GUI closes.", ["id": ["type": "string"]], required: ["id"])
        ]
    }

    private func json(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }

    private func write(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }

    private func writeError(id: Any, code: Int, message: String) {
        write(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }
}

enum MCPError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}

let arguments = CommandLine.arguments
if arguments.contains("--help") {
    print("HarsharkNGX MCP 1.0.0\nUsage: harsharkngx-mcp [--session-directory PATH]\nRuns a standalone MCP stdio server. Use load_har to open a file.")
} else if arguments.contains("--version") {
    print("1.0.0")
} else {
    let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.teezyyoxo.HarsharkNGX/Data/Library/Application Support/HarsharkNGX/Sessions", isDirectory: true)
    let directory: URL
    if let index = arguments.firstIndex(of: "--session-directory"), arguments.indices.contains(index + 1) {
        directory = URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath)
    } else { directory = defaultDirectory }
    MCPServer(sessionDirectory: directory).run()
}
