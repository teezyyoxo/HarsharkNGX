import Foundation
import Testing
import AppKit
@testable import HarsharkNGX

struct HarsharkNGXTests {
    @Test @MainActor func requestCellColorsFollowSelectionAndReuse() {
        let cell = RequestTableCell()
        let field = NSTextField(labelWithString: "POST")
        cell.addSubview(field)
        cell.textField = field
        cell.normalTextColor = NativeColors.method("POST")
        #expect(field.textColor == cell.normalTextColor)

        cell.backgroundStyle = .emphasized
        #expect(field.textColor == NSColor.alternateSelectedControlTextColor)
        // Reloading or reusing a selected cell must preserve selection contrast.
        cell.normalTextColor = NativeColors.status(500)
        #expect(field.textColor == NSColor.alternateSelectedControlTextColor)

        cell.backgroundStyle = .normal
        #expect(field.textColor == cell.normalTextColor)
    }

    @Test @MainActor func mcpDefaultsOnAndTogglePersistsAcrossWorkspaces() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let access = MCPAccessControl(sessionDirectory: directory)
        let workspace = Workspace(mcpAccess: access)
        #expect(workspace.mcpEnabled)
        workspace.toggleMCP()
        #expect(!workspace.mcpEnabled)
        #expect(try !access.read().enabled)
        let reopened = Workspace(mcpAccess: access)
        #expect(!reopened.mcpEnabled)
        reopened.toggleMCP()
        #expect(reopened.mcpEnabled)
        #expect(try access.read().enabled)
    }

    @Test @MainActor func failedMCPToggleReportsErrorWithoutChangingDisplayedState() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let access = MCPAccessControl(sessionDirectory: file)
        let workspace = Workspace(mcpAccess: access)
        #expect(workspace.mcpEnabled)
        try Data().write(to: file)
        workspace.toggleMCP()
        #expect(workspace.mcpEnabled)
        #expect(workspace.errorMessage != nil)
    }

    @Test @MainActor func captureLifecyclePreservesOtherSessionsAndReleasesClosedSession() throws {
        let workspace = Workspace()
        func session() throws -> HARSession {
            let archive = try HARParser().parse(Data(#"{"log":{"entries":[]}}"#.utf8))
            return HARSession(archive: archive, url: nil, name: "Fixture", rows: [])
        }
        var first: HARSession? = try session()
        let second = try session()
        weak var released = first
        workspace.sessions = [try #require(first), second]
        workspace.selectedSessionID = second.id
        workspace.close(try #require(first))
        first = nil
        #expect(released == nil)
        #expect(workspace.selectedSessionID == second.id)
        let third = try session()
        workspace.sessions.append(third)
        workspace.close(second)
        #expect(workspace.selectedSessionID == third.id)
        workspace.close(third)
        #expect(workspace.sessions.isEmpty)
        #expect(workspace.selectedSession == nil)
    }

    @Test @MainActor func latestFilterWinsAndKeepsSelectionValid() async throws {
        let archive = try HARParser().parse(Data(#"{"log":{"entries":[{"request":{"url":"https://first.test"},"response":{}},{"request":{"url":"https://second.test"},"response":{}}]}}"#.utf8))
        let session = HARSession(archive: archive, url: nil, name: "Fixture", rows: archive.entries.map(HARRow.init))
        session.query = "first"
        session.filter()
        session.query = "second"
        session.filter()
        for _ in 0..<100 {
            if !session.filtering { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(session.visibleRows.map(\.host) == ["second.test"])
        #expect(session.selectedEntry?.url == "https://second.test")
        session.query = "absent"
        session.filter()
        for _ in 0..<100 {
            if !session.filtering { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(session.visibleRows.isEmpty)
        #expect(session.selectedEntry == nil)
    }

    @Test @MainActor func bookmarksRestoreMultipleCapturesAndForgetClosedOnes() async throws {
        let suiteName = "HarsharkNGX.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set("Restore", forKey: "startup")
        defaults.set(true, forKey: "reuseCapture")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = ["One.har", "Two.har"].map { directory.appendingPathComponent($0) }
        for url in urls { try Data(#"{"log":{"entries":[]}}"#.utf8).write(to: url) }
        let first = Workspace(defaults: defaults)
        first.open(urls)
        for _ in 0..<200 {
            if first.sessions.count == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(first.sessions.count == 2)
        #expect((defaults.array(forKey: "captureBookmarks") as? [Data])?.count == 2)
        let restored = Workspace(defaults: defaults)
        restored.startup()
        for _ in 0..<200 {
            if restored.sessions.count == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(restored.sessions.map(\.name) == ["One.har", "Two.har"])
        for session in restored.sessions { restored.close(session) }
        #expect((defaults.array(forKey: "captureBookmarks") as? [Data])?.isEmpty == true)
        defaults.set("Welcome", forKey: "startup")
        restored.persistSessions()
        #expect(defaults.object(forKey: "captureBookmarks") == nil)
    }

    @Test func fixtureFlowsFromParserToInspector() throws {
        let json = #"{"log":{"entries":[{"request":{"method":"POST","url":"https://example.test/api","postData":{"text":"{\"enabled\":true}","mimeType":"application/json"}},"response":{"status":200,"httpVersion":"HTTP/2","content":{"text":"eyJvayI6dHJ1ZX0=","encoding":"base64","mimeType":"application/json"}},"time":42}]}}"#
        let archive = try HARParser().parse(Data(json.utf8))
        let entry = try #require(archive.entries.first)
        let row = HARRow(entry: entry)
        #expect(row.host == "example.test")
        #expect(row.httpVersion == "HTTP/2")
        #expect(row.matches("POST"))
        let detail = HARFormatter.detail(entry: entry, response: true, tab: .body, pretty: true)
        #expect(detail.syntax == "json")
        #expect(detail.text.contains("\"ok\""))
        #expect(detail.notice.isEmpty)
    }

    @Test @MainActor func smallInspectorPreviewsAreImmediateAndLargeOnesStayAsynchronous() throws {
        let small = try HARParser().parse(Data(#"{"log":{"entries":[{"request":{"postData":{"text":"hello"}},"response":{"content":{"text":"world"}}}]}}"#.utf8))
        let entry = try #require(small.entries.first)
        for response in [false, true] {
            let detail = InspectorPreparation.immediateDetail(entry: entry, response: response,
                tab: .body, pretty: true, maximumBodyBytes: 1024)
            #expect(detail?.text == (response ? "world" : "hello"))
        }
        let largeJSON = #"{"log":{"entries":[{"request":{},"response":{"content":{"text":""#
            + String(repeating: "x", count: 70_000) + #""}}}]}}"#
        let large = try HARParser().parse(Data(largeJSON.utf8))
        #expect(InspectorPreparation.immediateDetail(entry: try #require(large.entries.first),
            response: true, tab: .body, pretty: true, maximumBodyBytes: 1024) == nil)
    }

    @Test func missingBodyIsExplained() throws {
        let archive = try HARParser().parse(Data(#"{"log":{"entries":[{"request":{},"response":{}}]}}"#.utf8))
        let entry = try #require(archive.entries.first)
        let detail = HARFormatter.detail(entry: entry, response: true, tab: .body, pretty: true)
        #expect(!detail.notice.isEmpty)
        #expect(detail.text.isEmpty)
    }
}
