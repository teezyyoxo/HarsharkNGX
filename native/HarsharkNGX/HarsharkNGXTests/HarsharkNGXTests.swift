import Foundation
import Testing
@testable import HarsharkNGX

struct HarsharkNGXTests {
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

    @Test func missingBodyIsExplained() throws {
        let archive = try HARParser().parse(Data(#"{"log":{"entries":[{"request":{},"response":{}}]}}"#.utf8))
        let entry = try #require(archive.entries.first)
        let detail = HARFormatter.detail(entry: entry, response: true, tab: .body, pretty: true)
        #expect(!detail.notice.isEmpty)
        #expect(detail.text.isEmpty)
    }
}
