import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class HARSession: Identifiable {
    let id: UUID
    let url: URL?
    let name: String
    let archive: HARArchive
    let rows: [HARRow]
    let maximumDuration: Double
    let errorCount: Int
    var rowRevision = 0
    var visibleRows: [HARRow]
    var selection: Int?
    var query = ""
    var searchBodies = false
    var errorsOnly = false
    var filtering = false
    var sharedWithMCP = false
    var sortColumn = "started"
    var ascending = true
    @ObservationIgnored private var filterTask: Task<Void, Never>?

    init(archive: HARArchive, url: URL?, name: String, rows: [HARRow]) {
        id = archive.sessionID
        self.archive = archive
        self.url = url
        self.name = name
        self.rows = rows
        visibleRows = rows
        searchBodies = UserDefaults.standard.bool(forKey: "defaultSearchDetails")
        maximumDuration = max(1, rows.map(\.duration).max() ?? 1)
        errorCount = rows.filter { $0.status >= 400 }.count
        selection = rows.first?.id
    }

    var selectedEntry: HAREntry? {
        guard let selection, archive.entries.indices.contains(selection) else { return nil }
        return archive.entries[selection]
    }

    func filter() {
        filterTask?.cancel()
        let rows = rows
        let archive = archive
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodies = searchBodies
        let previewBytes = AppPreferences.previewBytes
        let errors = errorsOnly
        let column = sortColumn
        let ascending = ascending
        filtering = true
        filterTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                let worker = Task.detached(priority: .userInitiated) {
                    var result: [HARRow] = []
                    for row in rows {
                        try Task.checkCancellation()
                        guard !errors || row.status >= 400 else { continue }
                        var matches = query.isEmpty || row.matches(query)
                        if !matches && bodies {
                            let entry = archive.entries[row.id]
                            matches = [entry.requestBody, entry.responseBody].contains { body in
                                switch body.capture {
                                case .text(let text): return text.localizedCaseInsensitiveContains(query)
                                case .encoded, .deferred:
                                    if case .text(let text) = body.presentation(maximumEncodedBytes: previewBytes) {
                                        return text.localizedCaseInsensitiveContains(query)
                                    }
                                    return false
                                default: return false
                                }
                            }
                            if !matches {
                                matches = [entry.request["headers"], entry.response["headers"], entry.request["queryString"],
                                           entry.request["cookies"], entry.response["cookies"],
                                           entry.request["postData"]?.object?["params"]]
                                    .contains { HARFormatter.json($0 ?? .null, pretty: false).localizedCaseInsensitiveContains(query) }
                            }
                        }
                        if matches { result.append(row) }
                    }
                    result.sort { left, right in
                        let comparison: ComparisonResult
                        switch column {
                        case "duration", "waterfall": comparison = left.duration == right.duration ? .orderedSame : (left.duration < right.duration ? .orderedAscending : .orderedDescending)
                        case "status": comparison = left.status == right.status ? .orderedSame : (left.status < right.status ? .orderedAscending : .orderedDescending)
                        case "size": comparison = left.size == right.size ? .orderedSame : (left.size < right.size ? .orderedAscending : .orderedDescending)
                        default: comparison = left.value(for: column).localizedStandardCompare(right.value(for: column))
                        }
                        if comparison == .orderedSame { return left.id < right.id }
                        return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
                    }
                    return result
                }
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard let self else { return }
                visibleRows = result
                rowRevision &+= 1
                if !result.contains(where: { $0.id == selection }) { selection = result.first?.id }
                filtering = false
            } catch {
                // A newer query owns the UI; cancelled work must not publish old rows.
            }
        }
    }

    func cancel() {
        filterTask?.cancel()
        filterTask = nil
    }
}

@MainActor @Observable
final class Workspace {
    static let shared = Workspace()
    private let defaults: UserDefaults

    private let mcpAccess: MCPAccessControl
    private(set) var mcpEnabled = false

    init(defaults: UserDefaults = .standard, mcpAccess: MCPAccessControl? = nil) {
        self.defaults = defaults
        self.mcpAccess = mcpAccess ?? MCPAccessControl(
            sessionDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("HarsharkNGX/Sessions", isDirectory: true)
        )
        do {
            mcpEnabled = try self.mcpAccess.read().enabled
        } catch {
            errorMessage = "Unable to read MCP access settings.\n\(error.localizedDescription)"
        }
    }

    func toggleMCP() {
        do {
            let enabled = try !mcpAccess.read().enabled
            try mcpAccess.setEnabled(enabled)
            mcpEnabled = enabled
        } catch {
            errorMessage = "Unable to change MCP access.\n\(error.localizedDescription)"
        }
    }
    var sessions: [HARSession] = []
    private var didStart = false
    private var restorationBookmarks: [String: Data] = [:]
    var selectedSessionID: UUID?
    var loadingNames: [String] = []
    var errorMessage: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var pendingURLs: [URL] = []
    @ObservationIgnored private var currentImportURL: URL?
    @ObservationIgnored private var reloadTasks: [UUID: Task<Void, Never>] = [:]

    var selectedSession: HARSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    func startup() {
        guard !didStart else { return }
        didStart = true
        if ProcessInfo.processInfo.arguments.contains("--sample") {
            openSample()
            return
        }
        // An explicit Finder/open event takes precedence over startup preferences.
        guard sessions.isEmpty, pendingURLs.isEmpty, loadTask == nil else { return }
        switch defaults.string(forKey: "startup") {
        case "Sample": openSample()
        case "Restore":
            let bookmarks = defaults.array(forKey: "captureBookmarks") as? [Data] ?? []
            var urls: [URL] = []
            for bookmark in bookmarks {
                do {
                    var stale = false
                    let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                      relativeTo: nil, bookmarkDataIsStale: &stale)
                    urls.append(url)
                } catch { errorMessage = "A previous capture could not be restored. Open it again using File → Open.\n\(error.localizedDescription)" }
            }
            open(urls)
        default: break
        }
    }

    func persistSessions() {
        guard defaults.string(forKey: "startup") == "Restore" else {
            defaults.removeObject(forKey: "captureBookmarks")
            return
        }
        let bookmarks = sessions.compactMap { session -> Data? in
            guard let url = session.url else { return nil }
            return restorationBookmarks[url.path]
        }
        defaults.set(bookmarks, forKey: "captureBookmarks")
    }

    func exportSanitizedCapture() {
        guard let session = selectedSession else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "redacted-summary.har"
        panel.allowedContentTypes = [UTType(filenameExtension: "har") ?? .json]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let archive = session.archive
            Task {
                do {
                    try await Task.detached {
                        let data = try HARSanitizer.summaryData(archive)
                        try data.write(to: url, options: .atomic)
                    }.value
                } catch { self?.errorMessage = error.localizedDescription }
            }
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "har") ?? .json, .json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Open one or more HTTP Archive files."
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK { self?.open(panel.urls) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func open(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            if defaults.bool(forKey: "reuseCapture"), let existing = sessions.first(where: { $0.url?.standardizedFileURL == url.standardizedFileURL }) {
                selectedSessionID = existing.id
            } else if !pendingURLs.contains(url), currentImportURL != url {
                pendingURLs.append(url)
            }
        }
        guard loadTask == nil else { return }
        loadTask = Task {
            // Import serially to bound peak memory when multiple files are dropped.
            while !pendingURLs.isEmpty {
                let url = pendingURLs.removeFirst()
                currentImportURL = url
                loadingNames = [url.lastPathComponent]
                let worker = Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let archive = try HARParser().read(from: url)
                    let rows = archive.entries.map(HARRow.init)
                    let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                    return (archive, rows, bookmark)
                }
                do {
                    let (archive, rows, bookmark) = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: { worker.cancel() }
                    try Task.checkCancellation()
                    let session = HARSession(archive: archive, url: url, name: url.lastPathComponent, rows: rows)
                    sessions.append(session)
                    restorationBookmarks[url.path] = bookmark
                    persistSessions()
                    selectedSessionID = session.id
                    NSDocumentController.shared.noteNewRecentDocumentURL(url)
                } catch is CancellationError {
                    break
                } catch {
                    errorMessage = "\(url.lastPathComponent)\n\(error.localizedDescription)"
                }
            }
            currentImportURL = nil
            loadingNames = []
            loadTask = nil
        }
    }

    func cancelLoading() {
        pendingURLs = []
        loadTask?.cancel()
    }

    func close(_ session: HARSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        session.cancel()
        reloadTasks.removeValue(forKey: session.id)?.cancel()
        sessions.remove(at: index)
        if let url = session.url, !sessions.contains(where: { $0.url == url }) {
            restorationBookmarks.removeValue(forKey: url.path)
        }
        persistSessions()
        if selectedSessionID == session.id {
            selectedSessionID = sessions.isEmpty ? nil : sessions[min(index, sessions.count - 1)].id
        }
    }

    func reload() {
        guard let session = selectedSession, let url = session.url else { return }
        // Keep the existing session until replacement import succeeds.
        let oldID = session.id
        let name = session.name
        reloadTasks[oldID]?.cancel()
        reloadTasks[oldID] = Task {
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let archive = try HARParser().read(from: url)
                    return (archive, archive.entries.map(HARRow.init))
                }
                let (archive, rows) = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard let index = sessions.firstIndex(where: { $0.id == oldID }) else { return }
                sessions[index].cancel()
                let replacement = HARSession(archive: archive, url: url, name: name, rows: rows)
                sessions[index] = replacement
                if selectedSessionID == oldID { selectedSessionID = replacement.id }
                reloadTasks.removeValue(forKey: oldID)
            } catch is CancellationError {
                // A closed capture or newer reload owns the state.
            } catch {
                errorMessage = error.localizedDescription
                reloadTasks.removeValue(forKey: oldID)
            }
        }
    }

    func openSample() {
        guard let url = Bundle.main.url(forResource: "Sample", withExtension: "har") else {
            errorMessage = "The sample capture is missing from the application bundle."
            return
        }
        open([url])
    }

    var sharedDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HarsharkNGX/Sessions", isDirectory: true)
    }

    func shareWithMCP(_ session: HARSession) {
        Task {
            do {
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("HarsharkNGX/Sessions", isDirectory: true)
                let data = session.archive.source
                let id = session.id.uuidString
                try await Task.detached {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                           attributes: [.posixPermissions: 0o700])
                    let url = directory.appendingPathComponent(id).appendingPathExtension("har")
                    try data.write(to: url, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                }.value
                session.sharedWithMCP = true
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func removeSharedCopy(_ session: HARSession) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HarsharkNGX/Sessions", isDirectory: true)
        do {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(session.id.uuidString).appendingPathExtension("har"))
            session.sharedWithMCP = false
        } catch { errorMessage = error.localizedDescription }
    }

    func exportBody(_ body: HARBody) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = body.mimeType?.contains("json") == true ? "body.json" : "body.bin"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    try await Task.detached {
                        let data: Data
                        switch body.capture {
                        case .text(let text): data = Data(text.utf8)
                        case .empty: data = Data()
                        case .deferred(let reference, let encoding):
                            let text = try reference.text()
                            if let encoding, !encoding.isEmpty {
                                guard encoding.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "base64",
                                      let decoded = Data(base64Encoded: Data(text.utf8.filter { ![UInt8(9), 10, 13, 32].contains($0) })) else {
                                    throw ExportError.unavailable("Invalid or unsupported body encoding.")
                                }
                                data = decoded
                            } else { data = Data(text.utf8) }
                        case .encoded(let text, let encoding):
                            guard encoding == "base64" else { throw ExportError.unavailable("Unsupported encoding: \(encoding)") }
                            let normalized = text.utf8.filter { ![UInt8(9), 10, 13, 32].contains($0) }
                            guard let decoded = Data(base64Encoded: Data(normalized)) else { throw ExportError.unavailable("Invalid base64.") }
                            data = decoded
                        default: throw ExportError.unavailable("No exportable body was captured.")
                        }
                        try data.write(to: url, options: .atomic)
                    }.value
                } catch { self?.errorMessage = error.localizedDescription }
            }
        }
    }
}

nonisolated enum ExportError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let reason): return reason }
    }
}
